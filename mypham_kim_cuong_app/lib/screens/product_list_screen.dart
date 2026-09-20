import 'package:flutter/material.dart';

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          const Text('Chưa có dữ liệu'),
          const SizedBox(height: 4),
          const Text(
            'Danh sách sản phẩm sẽ hiển thị ở MVP-4',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}