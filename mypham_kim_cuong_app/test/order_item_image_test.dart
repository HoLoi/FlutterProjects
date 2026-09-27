import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mypham_kim_cuong_app/data/api_order_repository.dart';
import 'package:mypham_kim_cuong_app/models/app_settings.dart';
import 'package:mypham_kim_cuong_app/models/order.dart';
import 'package:mypham_kim_cuong_app/screens/order_detail_screen.dart';
import 'package:mypham_kim_cuong_app/screens/order_list_screen.dart';
import 'package:mypham_kim_cuong_app/services/api_client.dart';
import 'package:mypham_kim_cuong_app/services/auth_session.dart';
import 'package:mypham_kim_cuong_app/widgets/product_image_box.dart';

/// PNG 2x2 hợp lệ (màu hồng) làm ảnh giả cho `Image.network` trong test.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAAXNSR0IArs4c6QAAAA'
  'RnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAASSURBVBhXYzhhU/Ef'
  'hKGMiv8AV5wJ7bdgu2wAAAAASUVORK5CYII=',
);

const String _okImagePath = '/son.jpg';
const String _okImageUrl = 'https://images.test$_okImagePath';
const String _parentImagePath = '/son-cha.jpg';
const String _parentImageUrl = 'https://images.test$_parentImagePath';
const String _brokenImagePath = '/hong.jpg';
const String _brokenImageUrl = 'https://images.test$_brokenImagePath';

const int _orderId = 669;

/// `HttpHeaders` là interface nên cần lớp giả riêng.
class _FakeHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('HttpHeaders không dùng trong test ảnh');
}

/// [Stream] giả cho `HttpClientResponse`.
///
/// `HttpClientResponse` phải là một `Stream<List<int>>` (qua `ByteStream`), nên
/// lớp này kế thừa `Stream` và chỉ mô phỏng phần HTTP mà `NetworkImage` dùng.
class _FakeImageResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeImageResponse({required this.statusCode, required this.stream});

  @override
  final int statusCode;

  /// Nội dung phản hồi, truyền vào qua named parameter để test điều khiển
  /// được thời điểm ảnh "tải xong".
  final Stream<List<int>> stream;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  int get contentLength => -1;

  /// `NetworkImage` đọc trạng thái nén khi gom byte; ảnh giả không nén.
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImageRequest implements HttpClientRequest {
  _FakeImageRequest(this._response);

  final HttpClientResponse _response;

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// `HttpClient` giả: mọi URL ảnh được trả về từ [routes], không ra ngoài mạng.
class _FakeImageClient implements HttpClient {
  _FakeImageClient(this.routes);

  final Map<String, _FakeImageResponse Function()> routes;

  /// Các URL thật sự được yêu cầu, dùng để kiểm chứng app gọi đúng ảnh.
  final List<Uri> requestedUrls = <Uri>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requestedUrls.add(url);
    final route = routes[url.path];
    if (route == null) {
      return _FakeImageRequest(_notFound());
    }
    return _FakeImageRequest(route());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  static _FakeImageResponse _notFound() {
    return _FakeImageResponse(
      statusCode: 404,
      stream: const Stream<List<int>>.empty(),
    );
  }
}

_FakeImageResponse _okImage() {
  return _FakeImageResponse(
    statusCode: 200,
    stream: Stream<List<int>>.value(_tinyPng),
  );
}

_FakeImageResponse _brokenImage() {
  return _FakeImageResponse(
    statusCode: 404,
    stream: const Stream<List<int>>.empty(),
  );
}

/// Ảnh tải treo: dùng để giữ trạng thái "đang tải" một cách xác định.
_FakeImageResponse _pendingImage(StreamController<List<int>> controller) {
  return _FakeImageResponse(statusCode: 200, stream: controller.stream);
}

http.Response _jsonResponse(Object body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

AuthSession _signedIn() {
  final session = AuthSession();
  session.signIn(username: 'demo', appPassword: 'abcd efgh ijkl');
  return session;
}

/// Một phần tử `line_items`, bám sát JSON production sau khi thêm `image_url`.
///
/// [imageUrl] và [sku] cố tình kiểu `Object?`/`String?` để test được cả trường
/// hợp server trả sai kiểu.
Map<String, Object?> _lineItem({
  required int id,
  required String name,
  Object? imageUrl,
  String? sku = 'KC-0001-RED',
  int variationId = 0,
  double quantity = 1,
  double price = 190000,
}) {
  return {
    'id': id,
    'product_id': 100 + id,
    'variation_id': variationId,
    'name': name,
    'sku': sku,
    'quantity': quantity,
    'price': price,
    'subtotal': price * quantity,
    'total': price * quantity,
    // null là trường hợp sản phẩm bị xoá hoặc chưa có ảnh.
    'image_url': imageUrl,
  };
}

/// `GET /orders/{id}` với [items] cho sẵn.
Map<String, Object?> _orderDetail(List<Map<String, Object?>> items) {
  return {
    'id': _orderId,
    'number': '$_orderId',
    'status': 'processing',
    'status_label': 'Đang xử lý',
    'date_created': '2026-09-27 10:00:00',
    'date_paid': null,
    'payment_method': 'cod',
    'payment_method_label': 'COD',
    'payment_status': 'unpaid',
    'currency': 'VND',
    'total': 570000,
    'customer': {
      'id': 0,
      'is_guest': true,
      'name': 'Nguyễn Thị A',
      'phone': '0900000000',
      'email': 'a@example.com',
    },
    'billing': {
      'first_name': 'Nguyễn Thị',
      'last_name': 'A',
      'address_1': '123 Nguyễn Huệ',
      'city': 'TP. Hồ Chí Minh',
    },
    'shipping': {'first_name': 'Nguyễn Thị', 'last_name': 'A', 'city': ''},
    'line_items': items,
    'wc_active': true,
    'customer_note': null,
    'subtotal': 570000,
    'discount_total': 0,
    'shipping_total': 0,
    'fee_total': 0,
    'refunded_total': 0,
    'created_via': 'checkout',
  };
}

/// Phần tử của `GET /orders` (thiếu 8 trường chỉ có ở chi tiết).
Map<String, Object?> _orderListItem(
  int id,
  List<Map<String, Object?>> items, {
  String? customerName,
  double total = 570000,
}) {
  return {
    ..._orderDetail(items),
    'id': id,
    'number': '$id',
    'total': total,
    'wc_active': null,
    'customer_note': null,
    'created_via': null,
    if (customerName != null)
      'customer': {
        'id': 0,
        'is_guest': true,
        'name': customerName,
        'phone': '0900000000',
        'email': 'a@example.com',
      },
  };
}

/// Repository giả: `/orders/{id}` trả chi tiết, `/orders` trả danh sách.
ApiOrderRepository _repository({
  List<Map<String, Object?>>? detailItems,
  List<Map<String, Object?>>? listItems,
}) {
  final session = _signedIn();
  final detail = _orderDetail(detailItems ?? const []);
  final list = listItems ?? const <Map<String, Object?>>[];
  return ApiOrderRepository(
    authSession: session,
    apiClient: ApiClient(
      authSession: session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/$_orderId')) {
          return _jsonResponse(detail);
        }
        return _jsonResponse({
          'wc_active': true,
          'count': list.length,
          'page': 1,
          'per_page': 20,
          'data': list,
        });
      }),
    ),
  );
}

Widget _detailApp(ApiOrderRepository repository) {
  return MaterialApp(
    home: OrderDetailScreen(orderId: _orderId, apiRepository: repository),
  );
}

Widget _listApp(ApiOrderRepository repository) {
  return MaterialApp(
    home: Scaffold(
      body: OrderListScreen(
        apiRepository: repository,
        authSession: _signedIn(),
      ),
    ),
  );
}

/// Chạy [body] với `HttpClient` giả cho `Image.network`.
///
/// `NetworkImage` giữ một `HttpClient` static dùng chung cho mọi ảnh, nên phải
/// dùng hook `debugNetworkImageHttpClientProvider` thay vì `HttpOverrides`.
///
/// Hook phải được gỡ trước khi test kết thúc vì `flutter_test` kiểm tra các
/// biến debug của painting còn nguyên vẹn.
Future<void> _withFakeImages(
  _FakeImageClient client,
  Future<void> Function() body,
) async {
  painting.debugNetworkImageHttpClientProvider = () => client;
  try {
    await body();
  } finally {
    painting.debugNetworkImageHttpClientProvider = null;
  }
}

/// Số ảnh đã tải xong và được vẽ ra (`Image` vẫn còn trong cây khi đang tải).
int _decodedImageCount(WidgetTester tester) {
  return tester
      .widgetList<RawImage>(find.byType(RawImage))
      .where((raw) => raw.image != null)
      .length;
}

/// Chờ tối đa [count] ảnh được giải mã và vẽ ra.
///
/// Giải mã ảnh chạy ở event loop thật của engine nên chỉ `pump` trong
/// `testWidgets` sẽ không bao giờ thấy ảnh; phải dùng `runAsync`.
Future<void> _waitForDecodedImages(WidgetTester tester, int count) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (_decodedImageCount(tester) >= count) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  fail('Chưa giải mã được $count ảnh sau khi chờ.');
}

/// Chờ [finder] xuất hiện bằng cách pump từng frame.
///
/// Không dùng `pumpAndSettle` vì `CircularProgressIndicator` của ảnh đang tải
/// quay liên tục nên sẽ không bao giờ settle.
Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Không thấy ${finder.describeMatch(Plurality.many)} sau khi chờ.');
}

/// Chờ đơn tải xong (phần tóm tắt đã dựng).
///
/// Chỉ gọi một lần ngay sau `pumpWidget`: sau khi cuộn xuống, card tóm tắt nằm
/// ngoài vùng dựng nên `find.text('Ngày tạo')` không còn khớp.
Future<void> _waitForOrderLoaded(WidgetTester tester) {
  return _pumpUntilFound(tester, find.text('Ngày tạo'));
}

/// Cuộn tới tiêu đề "Sản phẩm (n)".
Future<void> _showItemsTitle(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.textContaining('Sản phẩm ('), 120);
  await tester.pump();
}

/// Cuộn tới line item [productName].
///
/// `scrollUntilVisible` tự kéo ListView khi phần tử chưa được dựng, nên không
/// cần biết trước vị trí cuộn. Màn chi tiết chỉ có một `Scrollable` nên
/// `scrollUntilVisible` dùng đúng ListView đó.
Future<void> _openDetailItem(WidgetTester tester, String productName) async {
  await tester.scrollUntilVisible(find.text(productName), 120);
  await tester.pump();
}

/// Chờ danh sách đơn tải xong và cuộn card của đơn [orderNumber] vào khung nhìn.
Future<void> _openOrderCard(WidgetTester tester, String orderNumber) async {
  await _pumpUntilFound(tester, find.text(orderNumber));
  // Màn danh sách có thêm thanh cuộn ngang của bộ lọc nên dùng ensureVisible
  // thay vì scrollUntilVisible (cần đúng một Scrollable).
  await tester.ensureVisible(find.text(orderNumber));
  await tester.pump();
}

/// Card của một line item hoặc một đơn, tìm theo tên hiển thị.
Finder _cardOf(String label) {
  return find.ancestor(of: find.text(label), matching: find.byType(Card));
}

/// Khung ảnh của một line item hoặc một đơn.
Finder _thumbOf(String label) {
  return find.descendant(
    of: _cardOf(label),
    matching: find.byType(ProductImageBox),
  );
}

/// `Image.network` của một line item hoặc một đơn.
Finder _networkImageOf(String label) {
  return find.descendant(of: _cardOf(label), matching: find.byType(Image));
}

/// Placeholder `Icons.spa` của một line item hoặc một đơn.
Finder _placeholderOf(String label) {
  return find.descendant(of: _cardOf(label), matching: find.byIcon(Icons.spa));
}

void main() {
  setUp(() {
    // Không dùng URL production trong test.
    AppSettings.baseUrl = 'https://demo.local';
    // Cache ảnh dùng chung giữa các test, xoá để mỗi test tự tải lại ảnh.
    PaintingBinding.instance.imageCache.clear();
  });

  group('ApiOrderParser - image_url của line item', () {
    test('parse được image_url của sản phẩm và biến thể', () {
      final order = ApiOrderParser.fromJson(
        _orderDetail([
          _lineItem(id: 1, name: 'Son Kem Lì Satin', imageUrl: _okImageUrl),
          _lineItem(
            id: 2,
            name: 'Son Kem Lì Satin - Màu đỏ',
            imageUrl: _parentImageUrl,
            variationId: 1001,
          ),
        ]),
      );

      expect(order.items.length, 2);
      expect(order.items[0].imageUrl, _okImageUrl);
      // Server đã fallback sang ảnh sản phẩm cha nên client nhận URL ảnh cha.
      expect(order.items[1].imageUrl, _parentImageUrl);
      expect(order.items[1].hasVariation, isTrue);
    });

    test('image_url null, thiếu hoặc chuỗi rỗng đều thành null', () {
      final order = ApiOrderParser.fromJson(
        _orderDetail([
          _lineItem(id: 1, name: 'Sản phẩm bị xoá'),
          _lineItem(id: 2, name: 'Ảnh chỉ có khoảng trắng', imageUrl: '   '),
          {
            ..._lineItem(id: 3, name: 'Không có trường image_url'),
          }..remove('image_url'),
          _lineItem(id: 4, name: 'image_url sai kiểu', imageUrl: 123),
        ]),
      );

      expect(order.items.length, 4);
      expect(order.items[0].imageUrl, isNull);
      expect(order.items[1].imageUrl, isNull);
      expect(order.items[2].imageUrl, isNull);
      // Server không đổi kiểu này; client chỉ ép chuỗi để không vỡ.
      expect(order.items[3].imageUrl, '123');
      // Các trường cũ vẫn parse bình thường.
      expect(order.items.first.name, 'Sản phẩm bị xoá');
      expect(order.items.first.sku, 'KC-0001-RED');
      expect(order.items.first.total, 190000);
    });

    test('danh sách và chi tiết cùng đọc image_url', () {
      final items = [_lineItem(id: 1, name: 'Son', imageUrl: _okImageUrl)];

      final fromList = ApiOrderParser.fromJson(_orderListItem(501, items));
      final fromDetail = ApiOrderParser.fromJson(_orderDetail(items));

      expect(fromList.items.single.imageUrl, _okImageUrl);
      expect(fromDetail.items.single.imageUrl, _okImageUrl);
    });
  });

  group('ProductImageBox.isRenderable', () {
    test('chỉ nhận URL http/https có host', () {
      expect(ProductImageBox.isRenderable(_okImageUrl), isTrue);
      expect(ProductImageBox.isRenderable('  $_okImageUrl  '), isTrue);
      expect(ProductImageBox.isRenderable(null), isFalse);
      expect(ProductImageBox.isRenderable(''), isFalse);
      expect(ProductImageBox.isRenderable('   '), isFalse);
      // Đường dẫn filesystem và scheme lạ không được đưa vào NetworkImage.
      expect(
        ProductImageBox.isRenderable('/wp-content/uploads/son.jpg'),
        isFalse,
      );
      expect(ProductImageBox.isRenderable('file:///uploads/son.jpg'), isFalse);
      expect(ProductImageBox.isRenderable('https://'), isFalse);
    });
  });

  testWidgets('Chi tiết đơn: có image_url thì hiện Image.network đúng URL', (
    tester,
  ) async {
    final client = _FakeImageClient({_okImagePath: _okImage});

    await _withFakeImages(client, () async {
      await tester.pumpWidget(
        _detailApp(
          _repository(
            detailItems: [
              _lineItem(
                id: 1,
                name: 'Son Kem Lì Satin',
                imageUrl: _okImageUrl,
                quantity: 2,
              ),
            ],
          ),
        ),
      );
      await _waitForOrderLoaded(tester);

      await _openDetailItem(tester, 'Son Kem Lì Satin');

      expect(_thumbOf('Son Kem Lì Satin'), findsOneWidget);
      expect(_networkImageOf('Son Kem Lì Satin'), findsOneWidget);
      // Ảnh đã về nên không còn placeholder.
      expect(_placeholderOf('Son Kem Lì Satin'), findsNothing);
      expect(client.requestedUrls.map((url) => url.path), [_okImagePath]);

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      expect(image.width, 56);
      expect(image.height, 56);
      expect((image.image as NetworkImage).url, _okImageUrl);
      // Thông tin dòng sản phẩm vẫn hiện đầy đủ.
      expect(find.text('SKU: KC-0001-RED'), findsOneWidget);
      expect(find.text('Số lượng: 2 · 190.000 đ'), findsOneWidget);
      expect(find.text('380.000 đ'), findsOneWidget);

      await _waitForDecodedImages(tester, 1);
      expect(_decodedImageCount(tester), 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Chi tiết đơn: image_url null hoặc rỗng hiện placeholder', (
    tester,
  ) async {
    // Không route nào trả ảnh: nếu app vô tình gọi ảnh, test sẽ thất bại.
    final client = _FakeImageClient({});

    await _withFakeImages(client, () async {
      await tester.pumpWidget(
        _detailApp(
          _repository(
            detailItems: [
              _lineItem(id: 1, name: 'Sản phẩm bị xoá'),
              _lineItem(id: 2, name: 'Ảnh rỗng', imageUrl: ''),
            ],
          ),
        ),
      );
      await _waitForOrderLoaded(tester);

      await _openDetailItem(tester, 'Sản phẩm bị xoá');

      expect(_networkImageOf('Sản phẩm bị xoá'), findsNothing);
      expect(_placeholderOf('Sản phẩm bị xoá'), findsOneWidget);
      expect(tester.getSize(_thumbOf('Sản phẩm bị xoá')), const Size(56, 56));

      await _openDetailItem(tester, 'Ảnh rỗng');
      expect(_networkImageOf('Ảnh rỗng'), findsNothing);
      expect(_placeholderOf('Ảnh rỗng'), findsOneWidget);
      expect(tester.getSize(_thumbOf('Ảnh rỗng')), const Size(56, 56));

      expect(find.byType(Image), findsNothing);
      expect(client.requestedUrls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Chi tiết đơn: ảnh lỗi quay lại placeholder và không crash', (
    tester,
  ) async {
    final client = _FakeImageClient({_brokenImagePath: _brokenImage});

    await _withFakeImages(client, () async {
      await tester.pumpWidget(
        _detailApp(
          _repository(
            detailItems: [
              _lineItem(
                id: 1,
                name: 'Son Hỏng Ảnh',
                imageUrl: _brokenImageUrl,
              ),
            ],
          ),
        ),
      );
      await _waitForOrderLoaded(tester);

      await _openDetailItem(tester, 'Son Hỏng Ảnh');

      // errorBuilder đã thay ảnh bằng placeholder.
      expect(_placeholderOf('Son Hỏng Ảnh'), findsOneWidget);
      expect(tester.getSize(_thumbOf('Son Hỏng Ảnh')), const Size(56, 56));
      expect(tester.takeException(), isNull);
      expect(client.requestedUrls.map((url) => url.path), [_brokenImagePath]);
    });
  });

  testWidgets('Chi tiết đơn: khung ảnh giữ 56x56 khi loading và khi lỗi', (
    tester,
  ) async {
    final controller = StreamController<List<int>>();
    final client = _FakeImageClient({
      _okImagePath: () => _pendingImage(controller),
      _brokenImagePath: _brokenImage,
    });

    await _withFakeImages(client, () async {
      await tester.pumpWidget(
        _detailApp(
          _repository(
            detailItems: [
              _lineItem(id: 1, name: 'Son Đang Tải', imageUrl: _okImageUrl),
              _lineItem(id: 2, name: 'Son Lỗi Ảnh', imageUrl: _brokenImageUrl),
              _lineItem(id: 3, name: 'Son Chưa Có Ảnh'),
            ],
          ),
        ),
      );

      // Giữ ảnh thứ nhất ở trạng thái đang tải để đo trước khi ảnh về.
      await _waitForOrderLoaded(tester);

      await _openDetailItem(tester, 'Son Đang Tải');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final loadingThumbSize = tester.getSize(_thumbOf('Son Đang Tải'));
      final loadingCardSize = tester.getSize(_cardOf('Son Đang Tải'));
      expect(loadingThumbSize, const Size(56, 56));

      await _openDetailItem(tester, 'Son Lỗi Ảnh');
      expect(_placeholderOf('Son Lỗi Ảnh'), findsOneWidget);
      expect(tester.getSize(_thumbOf('Son Lỗi Ảnh')), const Size(56, 56));

      await _openDetailItem(tester, 'Son Chưa Có Ảnh');
      expect(_placeholderOf('Son Chưa Có Ảnh'), findsOneWidget);
      expect(tester.getSize(_thumbOf('Son Chưa Có Ảnh')), const Size(56, 56));

      // Cho ảnh thứ nhất tải xong rồi so kích thước.
      await _openDetailItem(tester, 'Son Đang Tải');
      controller.add(_tinyPng);
      await controller.close();
      await _waitForDecodedImages(tester, 1);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getSize(_thumbOf('Son Đang Tải')), const Size(56, 56));
      // Card giữ nguyên chiều cao dù ảnh chuyển từ loading sang ảnh thật.
      expect(
        tester.getSize(_cardOf('Son Đang Tải')).height,
        loadingCardSize.height,
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Chi tiết đơn: nhiều line item hiển thị đúng ảnh và thông tin', (
    tester,
  ) async {
    final client = _FakeImageClient({
      _okImagePath: _okImage,
      _brokenImagePath: _brokenImage,
    });

    await _withFakeImages(client, () async {
      await tester.pumpWidget(
        _detailApp(
          _repository(
            detailItems: [
              _lineItem(
                id: 1,
                name: 'Son Kem Lì Satin',
                imageUrl: _okImageUrl,
                quantity: 2,
                variationId: 1001,
              ),
              _lineItem(
                id: 2,
                name: 'Kem Chống Nắng',
                imageUrl: _brokenImageUrl,
                sku: 'KC-0002',
                price: 189000,
              ),
              _lineItem(
                id: 3,
                name: 'Serum Vitamin C',
                sku: null,
                price: 210000,
              ),
            ],
          ),
        ),
      );
      await _waitForOrderLoaded(tester);
      await _showItemsTitle(tester);
      expect(find.text('Sản phẩm (3)'), findsOneWidget);

      // Dòng 1: có ảnh riêng của variation, giá và số lượng đầy đủ.
      await _openDetailItem(tester, 'Son Kem Lì Satin');
      await _waitForDecodedImages(tester, 1);
      expect(_thumbOf('Son Kem Lì Satin'), findsOneWidget);
      expect(_placeholderOf('Son Kem Lì Satin'), findsNothing);
      expect(find.text('Biến thể'), findsOneWidget);
      expect(find.text('SKU: KC-0001-RED'), findsOneWidget);
      expect(find.text('Số lượng: 2 · 190.000 đ'), findsOneWidget);
      expect(find.text('380.000 đ'), findsOneWidget);

      // Dòng 2: ảnh lỗi nên về placeholder.
      await _openDetailItem(tester, 'Kem Chống Nắng');
      expect(_thumbOf('Kem Chống Nắng'), findsOneWidget);
      expect(_placeholderOf('Kem Chống Nắng'), findsOneWidget);
      expect(find.text('SKU: KC-0002'), findsOneWidget);
      expect(find.text('Số lượng: 1 · 189.000 đ'), findsOneWidget);
      expect(find.text('189.000 đ'), findsOneWidget);

      // Dòng 3: không có image_url nên về placeholder, SKU thiếu.
      await _openDetailItem(tester, 'Serum Vitamin C');
      expect(_thumbOf('Serum Vitamin C'), findsOneWidget);
      expect(_placeholderOf('Serum Vitamin C'), findsOneWidget);
      expect(find.text('SKU: Chưa có SKU'), findsOneWidget);
      expect(find.text('Số lượng: 1 · 210.000 đ'), findsOneWidget);
      expect(find.text('210.000 đ'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Chi tiết đơn không overflow trên màn hình điện thoại', (
    tester,
  ) async {
    // iPhone SE nhỏ nhất: 375x667, mật độ chuẩn.
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = StreamController<List<int>>();
    final client = _FakeImageClient({
      _okImagePath: () => _pendingImage(controller),
      _brokenImagePath: _brokenImage,
    });
    const longName =
        'Son Kem Lì Satin Đỏ Dưỡng Môi Siêu Mềm Phiên Bản Giới Hạn 2026';

    await _withFakeImages(client, () async {
      await tester.pumpWidget(
        _detailApp(
          _repository(
            detailItems: [
              _lineItem(
                id: 1,
                name: longName,
                imageUrl: _okImageUrl,
                sku: 'KC-0001-RED-SATIN-LIMITED-2026',
                quantity: 3,
                price: 1230000,
              ),
              _lineItem(
                id: 2,
                name: 'Kem Chống Nắng SPF 50+ Dưỡng Sáng Da',
                imageUrl: _brokenImageUrl,
                sku: 'KC-0003-SPF50',
                price: 189000,
              ),
              _lineItem(id: 3, name: 'Sản phẩm chưa có ảnh', price: 75000),
            ],
          ),
        ),
      );
      await _waitForOrderLoaded(tester);
      await _showItemsTitle(tester);
      expect(find.text('Sản phẩm (3)'), findsOneWidget);

      // Ảnh thứ nhất còn đang tải, ảnh thứ hai lỗi, ảnh thứ ba không có URL.
      await _openDetailItem(tester, longName);
      expect(tester.getSize(_thumbOf(longName)), const Size(56, 56));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await _openDetailItem(tester, 'Kem Chống Nắng SPF 50+ Dưỡng Sáng Da');
      expect(
        tester.getSize(_thumbOf('Kem Chống Nắng SPF 50+ Dưỡng Sáng Da')),
        const Size(56, 56),
      );

      await _openDetailItem(tester, 'Sản phẩm chưa có ảnh');
      expect(
        tester.getSize(_thumbOf('Sản phẩm chưa có ảnh')),
        const Size(56, 56),
      );
      // Không có RenderFlex overflow: Flutter sẽ ghi lỗi vào test nếu tràn.
      expect(tester.takeException(), isNull);

      controller.add(_tinyPng);
      await controller.close();
      await _waitForDecodedImages(tester, 1);

      await _openDetailItem(tester, longName);
      expect(tester.getSize(_thumbOf(longName)), const Size(56, 56));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Danh sách đơn: hiện thumbnail nhỏ của sản phẩm đầu tiên', (
    tester,
  ) async {
    final client = _FakeImageClient({_okImagePath: _okImage});

    await _withFakeImages(client, () async {
      await tester.pumpWidget(
        _listApp(
          _repository(
            listItems: [
              _orderListItem(
                501,
                [
                  _lineItem(
                    id: 1,
                    name: 'Son Kem Lì Satin',
                    imageUrl: _okImageUrl,
                  ),
                ],
                total: 398000,
              ),
              _orderListItem(502, [_lineItem(id: 2, name: 'Kem Chống Nắng')]),
            ],
          ),
        ),
      );
      await _openOrderCard(tester, '#501');
      await _waitForDecodedImages(tester, 1);

      // Mỗi đơn có một khung ảnh nhỏ 40x40.
      expect(find.byType(ProductImageBox), findsNWidgets(2));
      expect(tester.getSize(_thumbOf('#501')), const Size(40, 40));
      expect(tester.getSize(_thumbOf('#502')), const Size(40, 40));
      // Đơn 501 có ảnh nên hiện Image.network, đơn 502 về placeholder.
      expect(_networkImageOf('#501'), findsOneWidget);
      expect(_placeholderOf('#501'), findsNothing);
      expect(_placeholderOf('#502'), findsOneWidget);
      expect(client.requestedUrls.map((url) => url.path), [_okImagePath]);
      // Nội dung danh sách cũ vẫn hiển thị.
      expect(find.text('2 đơn hàng'), findsOneWidget);
      expect(find.text('1 sản phẩm · COD'), findsNWidgets(2));
      expect(find.text('398.000 đ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Danh sách đơn không overflow trên màn hình điện thoại', (
    tester,
  ) async {
    // Màn hình nhỏ phổ biến: 360x640.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final client = _FakeImageClient({
      _okImagePath: _okImage,
      _brokenImagePath: _brokenImage,
    });
    const longCustomer = 'Nguyễn Thị A Mỹ Anh Phiên Bản Giới Hạn';

    await _withFakeImages(client, () async {
      await tester.pumpWidget(
        _listApp(
          _repository(
            listItems: [
              _orderListItem(
                501,
                [
                  _lineItem(
                    id: 1,
                    name: 'Son Kem Lì Satin Đỏ Dưỡng Môi Siêu Mềm',
                    imageUrl: _okImageUrl,
                    price: 1230000,
                  ),
                ],
                customerName: longCustomer,
              ),
              _orderListItem(502, [
                _lineItem(
                  id: 2,
                  name: 'Kem Chống Nắng',
                  imageUrl: _brokenImageUrl,
                  price: 189000,
                ),
              ]),
            ],
          ),
        ),
      );
      await _openOrderCard(tester, '#501');
      await _waitForDecodedImages(tester, 1);

      expect(tester.getSize(_thumbOf('#501')), const Size(40, 40));
      expect(tester.getSize(_thumbOf('#502')), const Size(40, 40));
      expect(_placeholderOf('#502'), findsOneWidget);
      // Tên khách dài không được làm tràn dòng.
      expect(find.textContaining(longCustomer), findsOneWidget);
      // Không có RenderFlex overflow: Flutter sẽ ghi lỗi vào test nếu tràn.
      expect(tester.takeException(), isNull);
    });
  });
}
