import 'package:flutter/material.dart';

class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.point_of_sale_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          const Text('Màn hình POS'),
          const SizedBox(height: 4),
          const Text(
            'Chưa có chức năng thanh toán (MVP-5)',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}