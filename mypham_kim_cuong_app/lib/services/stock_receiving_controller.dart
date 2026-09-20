import 'package:flutter/foundation.dart';

import '../models/stock_receiving.dart';

class StockReceivingController extends ChangeNotifier {
  final List<StockReceiving> _records = [];
  int _nextId = 1;

  List<StockReceiving> get records => List.unmodifiable(_records);

  int get recordCount => _records.length;

  StockReceiving create({
    required List<StockReceivingItem> items,
    String? note,
  }) {
    final trimmedNote = note?.trim();
    final record = StockReceiving(
      id: _nextId++,
      createdAt: DateTime.now(),
      items: items,
      note: (trimmedNote == null || trimmedNote.isEmpty)
          ? null
          : trimmedNote,
    );
    _records.insert(0, record);
    notifyListeners();
    return record;
  }
}