import 'package:flutter/material.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const CustomAppBar({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      actions: [IconButton(icon: Icon(Icons.shopping_cart), onPressed: () {})],
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight);
}
