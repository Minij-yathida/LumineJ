# 💎 LuminéJ – Flutter Jewelry Shop App

A modern jewelry e-commerce application built with **Flutter** and **Firebase**.  
Designed with an elegant **cream-brown-rose-gold** theme and focused on smooth user experience for both customers and admins.

---

## ✨ Features

### 🛍️ Customer Side
- Browse jewelry products with images, details, and variants  
- Add to cart, apply coupons, and checkout with multiple payment options  
- Upload PromptPay slip or choose Cash on Delivery (COD)  
- Track order status in real-time  
- Chat with store support directly  
- Manage user profile, address, and order history

### 🧭 Admin Side
- Manage products (add, edit, delete, upload images to ImgBB)  
- Handle orders and update statuses  
- Approve or reject payment slips  
- Manage discount coupons and monitor usage  
- Receive admin notifications instantly

---

## 🔧 Tech Stack

| Category | Technology |
|-----------|-------------|
| Frontend | Flutter 3.35.7 (Dart 3.9.2) |
| Backend | Firebase (Firestore, Storage, Auth, Functions, FCM) |
| Image Hosting | ImgBB API |
| Database | Cloud Firestore |
| State Management | Provider / StreamBuilder |
| Notifications | Firebase Cloud Messaging (FCM) |
| Auth | Firebase Auth (email/phone) |

---

## 🧱 Project Setup

### 1️⃣ Clone the repo
```bash
git clone https://github.com/Minij-yathida/LumineJ.git
cd LumineJ

2️⃣ Install dependencies
flutter pub get

3️⃣ Connect Firebase

Add your google-services.json to /android/app

Add your GoogleService-Info.plist to /ios/Runner (if using iOS)

4️⃣ Run the app
flutter run

🛠️ Build Release (Android)

To generate a signed release APK:

flutter build apk --release


The output will be located at:

build/app/outputs/flutter-apk/app-release.apk

🧑‍💻 Developer

Yathida Inthapaet
📧 Email: yathidakan@gmail.com

🌐 GitHub: Minij-yathida

📜 License

This project is licensed under the MIT License – feel free to use and modify.