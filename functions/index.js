// functions/index.js
import 'dotenv/config';                     // ใช้ .env ตอนพัฒนา local
import functions from 'firebase-functions';
import admin from 'firebase-admin';
import fetch from 'node-fetch';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const REGION = process.env.FUNCTION_REGION || 'asia-southeast1';
const SENDGRID_API_KEY = process.env.SENDGRID_API_KEY || '';
const SEND_FROM_EMAIL = process.env.SEND_FROM_EMAIL || 'teamluminej@gmail.com';
const SEND_FROM_NAME  = process.env.SEND_FROM_NAME  || 'Luminé J';
const IMGBB_KEY = process.env.IMGBB_KEY || '';

// ---------------- Utils ----------------
const nowTs = () => admin.firestore.Timestamp.now();
const clampMoney = (n) => Math.max(0, Number.isFinite(+n) ? +n : 0);
const codeOf = (c) => String(c || '').trim().toUpperCase();

const isTimestampExpired = (ts) => {
  if (!ts) return false;
  try {
    const d = ts.toDate ? ts.toDate() : new Date(String(ts));
    return d.getTime() < Date.now();
  } catch {
    return true;
  }
};

// ---------------- Stock helpers ----------------

// สร้าง key สำหรับ stock_map (color__size)
const makeVariantKey = (variant = {}) => {
  const color = (variant.color || 'default').toString().trim().toLowerCase();
  const size  = (variant.size  || 'default').toString().trim().toLowerCase();
  return `${color}__${size}`;
};

// อ่าน stock ที่สามารถขายได้ จาก product + variant
// ลำดับความสำคัญ: stock_map → variants[].stock → stock รวม
function resolveAvailableStock(product, variant = {}) {
  const key = makeVariantKey(variant);
  const stockMap = product.stock_map || product.stockMap || null;

  // 1) มี stock_map ตาม key
  if (stockMap && Object.prototype.hasOwnProperty.call(stockMap, key)) {
    const n = Number(stockMap[key]);
    if (Number.isFinite(n)) return n;
  }

  // 2) มี variants[]
  if (Array.isArray(product.variants) && product.variants.length > 0) {
    const found = product.variants.find((v) => {
      const colors = Array.isArray(v.color)
        ? v.color.map((c) => c.toString().toLowerCase())
        : [];
      const sizes = Array.isArray(v.sizes)
        ? v.sizes.map((s) => s.toString().toLowerCase())
        : typeof v.sizes === 'string'
          ? [v.sizes.toString().toLowerCase()]
          : [];

      const hasVariantColor = !!variant.color;
      const hasVariantSize  = !!variant.size;

      const colorOk = !hasVariantColor || colors.length === 0
        ? true
        : colors.includes(variant.color.toString().toLowerCase());

      const sizeOk = !hasVariantSize || sizes.length === 0
        ? true
        : sizes.includes(variant.size.toString().toLowerCase());

      return colorOk && sizeOk;
    });

    if (found && typeof found.stock === 'number') {
      const n = Number(found.stock);
      if (Number.isFinite(n)) return n;
    }
  }

  // 3) fallback → ใช้ stock รวมบน document
  const top = Number(product.stock);
  return Number.isFinite(top) ? top : 0;
}

// สร้าง update object สำหรับตัดสต็อก ให้สอดคล้องกับ resolveAvailableStock
function buildStockUpdate(product, variant = {}, qty) {
  const key = makeVariantKey(variant);
  const stockMap = product.stock_map || product.stockMap || null;
  const update = {};

  // 1) ถ้ามีใน stock_map → หักที่ stock_map
  if (stockMap && Object.prototype.hasOwnProperty.call(stockMap, key)) {
    update[`stock_map.${key}`] = admin.firestore.FieldValue.increment(-qty);
    return update;
  }

  // 2) ถ้ามี variants[] และหาเจอ → หักที่ variants[idx].stock
  if (Array.isArray(product.variants) && product.variants.length > 0) {
    const idx = product.variants.findIndex((v) => {
      const colors = Array.isArray(v.color)
        ? v.color.map((c) => c.toString().toLowerCase())
        : [];
      const sizes = Array.isArray(v.sizes)
        ? v.sizes.map((s) => s.toString().toLowerCase())
        : typeof v.sizes === 'string'
          ? [v.sizes.toString().toLowerCase()]
          : [];

      const hasVariantColor = !!variant.color;
      const hasVariantSize  = !!variant.size;

      const colorOk = !hasVariantColor || colors.length === 0
        ? true
        : colors.includes(variant.color.toString().toLowerCase());

      const sizeOk = !hasVariantSize || sizes.length === 0
        ? true
        : sizes.includes(variant.size.toString().toLowerCase());

      return colorOk && sizeOk;
    });

    if (idx >= 0 && typeof product.variants[idx].stock === 'number') {
      update[`variants.${idx}.stock`] = admin.firestore.FieldValue.increment(-qty);
      return update;
    }
  }

  // 3) fallback → หัก stock รวม
  update.stock = admin.firestore.FieldValue.increment(-qty);
  return update;
}

// ===================== Admin Notifications (in-app) =====================

/**
 * สร้าง / อัปเดตแจ้งเตือนออเดอร์ใหม่สำหรับฝั่งแอดมิน
 * collection: notifications_admin/{orderId}
 */
async function upsertAdminOrderNotification(orderId, orderData = {}) {
  if (!orderId) return;

  const pricing = orderData.pricing || {};
  const total = clampMoney(
    pricing.grandTotal ??
    orderData.total ??
    pricing.total ??
    pricing.subtotal ??
    0,
  );

  const customerName =
    (orderData.customer && orderData.customer.name) || 'Customer';

  const ref = db.collection('notifications_admin').doc(orderId);
  const snap = await ref.get();

  const base = {
    orderId,
    title: 'New order received',
    body: `Order #${orderId} placed by ${customerName}.`,
    total,
    createdAt: orderData.createdAt || nowTs(),
  };

  if (!snap.exists) {
    await ref.set({
      ...base,
      read: false,
    });
  } else {
    await ref.set(
      {
        ...base,
        updatedAt: nowTs(),
      },
      { merge: true },
    );
  }
}


// ===================== Triggers / Callables =====================

// ---------- Trigger: send email on order create (ปิด) ----------
export const notifyOnOrderCreated = functions
  .region(REGION)
  .firestore.document('orders/{orderId}')
  .onCreate(async (snap, context) => {
    const orderId = context.params.orderId;
    const data = snap.data() || {};
    try {
      await upsertAdminOrderNotification(orderId, data);
      console.log('[notifyOnOrderCreated] admin notification created for', orderId);
    } catch (e) {
      console.error('[notifyOnOrderCreated] failed:', e);
    }
    return null;
  });


// ---------- Callable: upload images to ImgBB ----------
export const uploadImagesToImgBB = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    const { images } = data || {};
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'UNAUTHORIZED');
    }
    if (!IMGBB_KEY) return { ok: false, reason: 'NO_IMGBB_KEY' };
    if (!Array.isArray(images) || images.length === 0) return { ok: false, reason: 'NO_IMAGES' };

    const urls = [];
    for (const b64 of images) {
      const form = new URLSearchParams();
      form.append('key', IMGBB_KEY);
      form.append('image', b64);
      const resp = await fetch('https://api.imgbb.com/1/upload', { method: 'POST', body: form });
      const json = await resp.json();
      if (!json?.success) {
        throw new functions.https.HttpsError('internal', 'IMGBB_UPLOAD_FAILED');
      }
      urls.push(json.data.url);
    }
    return { ok: true, urls };
  });

export const uploadSlipToImgbb = uploadImagesToImgBB;

// ---------- Callable: applyCoupon (คำนวณส่วนลดสินค้าอย่างเดียว) ----------
export const applyCoupon = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    const { userId, code, subtotal } = data || {};
    if (!context.auth || context.auth.uid !== userId) return { ok: false, reason: 'UNAUTHORIZED' };
    if (!code || typeof subtotal !== 'number') return { ok: false, reason: 'INVALID_INPUT' };

    const couponCode = codeOf(code);

    const snap = await db.collection('coupons').where('code', '==', couponCode).limit(1).get();
    if (snap.empty) return { ok: false, reason: 'NOT_FOUND' };
    const c = snap.docs[0].data();

    if (c.active !== true) return { ok: false, reason: 'INACTIVE' };
    if (isTimestampExpired(c.expiresAt)) return { ok: false, reason: 'EXPIRED' };
    if (typeof c.minSpend === 'number' && subtotal < c.minSpend) return { ok: false, reason: 'MIN_SPEND' };
    if (typeof c.usageLimit === 'number' && (c.usedCount || 0) >= c.usageLimit) {
      return { ok: false, reason: 'LIMIT_REACHED' };
    }

    if (typeof c.perUserLimit === 'number') {
      const usageDoc = await db.collection('coupon_usages').doc(couponCode)
        .collection('users').doc(userId).get();
      const used = usageDoc.exists ? (usageDoc.data()?.count || 0) : 0;
      if (used >= c.perUserLimit) return { ok: false, reason: 'PER_USER_LIMIT' };
    }

    // ส่วนลดสินค้า (ไม่รวมค่าส่ง)
    let discount = 0;
    if (c.type === 'percent') {
      discount = (Number(c.value) / 100) * subtotal;
      if (c.maxDiscount) discount = Math.min(discount, Number(c.maxDiscount));
    } else if (c.type === 'fixed') {
      discount = Number(c.value);
    }
    discount = Math.max(0, Math.min(discount, subtotal));

    return { ok: true, discount };
  });

// ---------- Callable: createOrder (ตัดสต็อก + สร้างออเดอร์) ----------
export const createOrder = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    const { userId, items, couponCode, customer, pricing, payment } = data || {};

    // -------- Validate --------
    if (!context.auth || context.auth.uid !== userId) {
      throw new functions.https.HttpsError('unauthenticated', 'UNAUTHORIZED');
    }
    if (!Array.isArray(items) || items.length === 0) {
      throw new functions.https.HttpsError('invalid-argument', 'EMPTY_CART');
    }

    const orderRef = db.collection('orders').doc();

    try {
      let result = null;

      await db.runTransaction(async (tx) => {
        let subtotal = 0;
        const finalizedItems = [];

        // 1) ตรวจสต็อก + เก็บรายการ
        for (const it of items) {
          const pid = String(it.productId || '');
          const qty = Number(it.qty || 0);
          if (!pid || qty <= 0) {
            throw new functions.https.HttpsError('invalid-argument', 'BAD_ITEM');
          }

          const pRef = db.collection('products').doc(pid);
          const pSnap = await tx.get(pRef);
          if (!pSnap.exists) {
            throw new functions.https.HttpsError('failed-precondition', `PRODUCT_NOT_FOUND:${pid}`);
          }
          const p = pSnap.data() || {};

          const available = resolveAvailableStock(p, it.variant || {});
          if (available < qty) {
            throw new functions.https.HttpsError('failed-precondition', `OUT_OF_STOCK:${pid}`);
          }

          const unitPrice = Number(p.price ?? p.basePrice ?? 0);
          subtotal += unitPrice * qty;

          finalizedItems.push({
            productId: pid,
            name: p.name || '',
            price: unitPrice,
            qty,
            variant: it.variant ?? null,
            image: Array.isArray(p.images) && p.images.length ? p.images[0] : null,
          });
        }

        // 2) ค่าส่ง
        const feeIn = pricing?.shippingFee != null ? Number(pricing.shippingFee) : 0;
        const shippingFee = clampMoney(feeIn);

        // 3) คูปอง
        let productDiscount = 0;
        let shippingDiscount = 0;
        let appliedCode = null;

        if (couponCode) {
          const code = codeOf(couponCode);

          // ต้องเป็นคูปองที่ claim แล้ว และยังไม่ใช้
          const claimRef = db.collection('users').doc(userId)
            .collection('claimedCoupons').doc(code);
          const claimSnap = await tx.get(claimRef);
          let claimed = false;
          let alreadyUsed = false;

          if (claimSnap.exists) {
            claimed = true;
            const d = claimSnap.data() || {};
            alreadyUsed = !!d.redeemedAt;
          } else {
            const q = await db.collection('users').doc(userId)
              .collection('claimedCoupons')
              .where('code', '==', code)
              .limit(1)
              .get();
            if (!q.empty) {
              claimed = true;
              const d = q.docs[0].data() || {};
              alreadyUsed = !!d.redeemedAt;
            }
          }

          if (!claimed) {
            throw new functions.https.HttpsError('failed-precondition', 'COUPON_NOT_CLAIMED');
          }
          if (alreadyUsed) {
            throw new functions.https.HttpsError('failed-precondition', 'COUPON_ALREADY_USED');
          }

          const cSnap = await db.collection('coupons')
            .where('code', '==', code)
            .limit(1)
            .get();
          if (cSnap.empty) {
            throw new functions.https.HttpsError('not-found', 'COUPON_NOT_FOUND');
          }

          const c = cSnap.docs[0].data() || {};

          if (c.active !== true) {
            throw new functions.https.HttpsError('failed-precondition', 'COUPON_INACTIVE');
          }
          if (isTimestampExpired(c.expiresAt)) {
            throw new functions.https.HttpsError('failed-precondition', 'COUPON_EXPIRED');
          }
          if (typeof c.minSpend === 'number' && subtotal < c.minSpend) {
            throw new functions.https.HttpsError('failed-precondition', 'COUPON_MIN_SPEND');
          }

          const type = String(c.type || '');
          const val = Number(c.value || 0);
          const cap = Number(c.maxDiscount ?? Number.POSITIVE_INFINITY);

          if (type.startsWith('shipping_')) {
            // ส่วนลดค่าส่ง
            let d = 0;
            if (type === 'shipping_fixed') d = val;
            else if (type === 'shipping_percent') d = shippingFee * (val / 100);
            else if (type === 'shipping_full') d = shippingFee;

            d = Math.min(d, cap);
            shippingDiscount = Math.max(0, Math.min(d, shippingFee));
          } else {
            // ส่วนลดสินค้า
            let d = (type === 'percent') ? subtotal * (val / 100) : val;
            d = Math.min(d, cap);
            productDiscount = Math.max(0, Math.min(d, subtotal));
          }

          if (productDiscount + shippingDiscount <= 0) {
            throw new functions.https.HttpsError('failed-precondition', 'COUPON_NOT_APPLICABLE');
          }

          appliedCode = code;
        }

        // 4) grand total
        const grandTotal =
          clampMoney(subtotal - productDiscount) +
          clampMoney(shippingFee - shippingDiscount);

        // 5) ตัดสต็อกตาม variant / stock_map
        for (const it of items) {
          const pid = String(it.productId || '');
          const qty = Number(it.qty || 0);

          const pRef = db.collection('products').doc(pid);
          const pSnap = await tx.get(pRef);
          if (!pSnap.exists) {
            throw new functions.https.HttpsError('failed-precondition', `PRODUCT_NOT_FOUND_AFTER_CHECK:${pid}`);
          }
          const p = pSnap.data() || {};
          const update = buildStockUpdate(p, it.variant || {}, qty);
          tx.update(pRef, update);
        }

        // 6) สร้าง order
        tx.set(orderRef, {
          userId,
          items: finalizedItems,
          total: grandTotal,
          pricing: {
            subtotal: +subtotal.toFixed(2),
            shippingFee: +shippingFee.toFixed(2),
            discount: +productDiscount.toFixed(2),
            shippingDiscount: +shippingDiscount.toFixed(2),
            grandTotal: +grandTotal.toFixed(2),
          },
          couponCode: appliedCode || null,
          customer: {
            name: customer?.name ?? '',
            address: customer?.address ?? '',
            phone: customer?.phone ?? '',
            email: customer?.email ?? '',
          },
          payment: {
            method: payment?.method === 'cod' ? 'cod' : 'transfer_qr',
            slipUrl: payment?.method === 'transfer_qr' ? (payment?.slipUrl || '') : '',
            status: payment?.method === 'cod' ? 'cod_pending' : 'proof_submitted',
          },
          shipping: {
            optionId: payment?.method === 'cod' ? 'cod' : 'standard',
            optionName: payment?.method === 'cod'
              ? 'Cash on Delivery (เก็บปลายทาง)'
              : 'Standard Delivery (ส่งธรรมดา)',
            calculatedFee: clampMoney(pricing?.shippingFee ?? 0),
          },
          status: payment?.method === 'cod' ? 'pending_cod' : 'waiting_admin',
          stockDeducted: true,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // 7) มาร์กคูปองว่าใช้แล้ว
        if (appliedCode) {
          const claimRef = db.collection('users').doc(userId)
            .collection('claimedCoupons').doc(appliedCode);
          tx.set(claimRef, { code: appliedCode }, { merge: true });
          tx.update(claimRef, {
            redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
            usedInOrderId: orderRef.id,
          });
        }

        result = {
          ok: true,
          orderId: orderRef.id,
          subtotal,
          total: grandTotal,
        };
      });

      // 8) สร้างแจ้งเตือนแอดมิน หลัง transaction ผ่าน
      try {
        const snap = await orderRef.get();
        if (snap.exists) {
          await upsertAdminOrderNotification(orderRef.id, snap.data() || {});
          console.log('[createOrder] admin notification created for', orderRef.id);
        } else {
          console.warn('[createOrder] order doc not found after transaction for', orderRef.id);
        }
      } catch (e) {
        console.error('[createOrder] failed to create admin notification:', e);
      }

      return result;
    } catch (err) {
      console.error('createOrder error:', err);

      if (err instanceof functions.https.HttpsError) {
        throw err;
      }

      const msg = String(err?.message || '');

      if (msg.includes('OUT_OF_STOCK')) {
        throw new functions.https.HttpsError('failed-precondition', 'OUT_OF_STOCK');
      }

      throw new functions.https.HttpsError(
        'internal',
        msg || 'Transaction failed unexpectedly.',
      );
    }
  });


// ---------- Chat triggers (ปิด) ----------
export const onThreadCreateWelcome = functions
  .region(REGION)
  .firestore.document('threads/{threadId}')
  .onCreate(async () => {
    console.log('onThreadCreateWelcome skipped (Notifications disabled for debug)');
    return null;
  });

export const onMessageCreated = functions
  .region(REGION)
  .firestore.document('threads/{threadId}/messages/{messageId}')
  .onCreate(async () => {
    console.log('onMessageCreated skipped (Notifications disabled for debug)');
    return null;
  });
