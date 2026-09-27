import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mypham_kim_cuong_app/data/api_product_repository.dart';
import 'package:mypham_kim_cuong_app/models/app_settings.dart';
import 'package:mypham_kim_cuong_app/screens/product_list_screen.dart';
import 'package:mypham_kim_cuong_app/services/api_client.dart';

/// PNG 2x2 hợp lệ (màu hồng) làm ảnh giả cho `Image.network` trong test.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAAXNSR0IArs4c6QAAAA'
  'RnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAASSURBVBhXYzhhU/Ef'
  'hKGMiv8AV5wJ7bdgu2wAAAAASUVORK5CYII=',
);

const String _okImagePath = '/son.jpg';
const String _okImageUrl = 'https://images.test$_okImagePath';
const String _brokenImagePath = '/hong.jpg';
const String _brokenImageUrl = 'https://images.test$_brokenImagePath';

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

ApiProductRepository _repository(List<Map<String, Object?>> data) {
  return ApiProductRepository(
    apiClient: ApiClient(
      httpClient: MockClient((_) async {
        return http.Response(
          jsonEncode({'wc_active': true, 'count': data.length, 'data': data}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
  );
}

Map<String, Object?> _product({
  required int id,
  required String name,
  String? imageUrl,
  String sku = 'KC-0001',
}) {
  return {
    'id': id,
    'name': name,
    'sku': sku,
    'barcode': '89300000000$id',
    'price': 189000,
    'regular_price': 220000,
    'sale_price': 189000,
    'stock_quantity': 25,
    'stock_status': 'instock',
    'image_url': imageUrl,
    'categories': [
      {'id': 1, 'name': 'Son', 'slug': 'son'},
    ],
  };
}

Widget _app(ApiProductRepository repository) {
  return MaterialApp(
    home: Scaffold(body: ProductListScreen(apiRepository: repository)),
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

/// Bật chế độ API rồi đợi vài frame cho ảnh về trạng thái ổn định.
///
/// Không dùng `pumpAndSettle` vì `CircularProgressIndicator` quay liên tục nên
/// sẽ không bao giờ settle trong lúc ảnh đang tải.
Future<void> _openApiList(WidgetTester tester) async {
  await tester.tap(find.byType(Switch));
  await tester.pump();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Card của một sản phẩm, tìm theo tên để không lẫn với card của switch.
Finder _cardOf(String productName) {
  return find.ancestor(of: find.text(productName), matching: find.byType(Card));
}

/// Vùng ảnh 48x48: Container đầu tiên trong card (badge trạng thái đứng sau).
Finder _thumbOf(String productName) {
  return find
      .descendant(of: _cardOf(productName), matching: find.byType(Container))
      .first;
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

void main() {
  setUp(() {
    // Không dùng URL production trong test.
    AppSettings.baseUrl = 'https://demo.local';
    // Cache ảnh dùng chung giữa các test, xoá để mỗi test tự tải lại ảnh.
    PaintingBinding.instance.imageCache.clear();
  });

  testWidgets('Sản phẩm có image_url hiển thị Image.network đúng URL', (
    tester,
  ) async {
    final client = _FakeImageClient({_okImagePath: _okImage});

    await _withFakeImages(client, () async {
      await tester.pumpWidget(
        _app(
          _repository([
            _product(id: 101, name: 'Son Kem Lì Satin', imageUrl: _okImageUrl),
          ]),
        ),
      );
      await _openApiList(tester);

      // Ảnh đã tải và vẽ ra: vẫn là Image.network và không còn placeholder.
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.spa), findsNothing);
      expect(client.requestedUrls.map((url) => url.path), [_okImagePath]);

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      expect(image.width, 48);
      expect(image.height, 48);
      expect((image.image as NetworkImage).url, _okImageUrl);

      await _waitForDecodedImages(tester, 1);
      expect(_decodedImageCount(tester), 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Sản phẩm không có image_url hiển thị placeholder Icons.spa', (
    tester,
  ) async {
    // Không route nào trả ảnh: nếu app vô tình gọi ảnh, test sẽ thất bại.
    final client = _FakeImageClient({});

    await _withFakeImages(client, () async {
      await tester.pumpWidget(
        _app(
          _repository([
            _product(id: 102, name: 'Kem Chống Nắng SPF 50'),
            _product(id: 103, name: 'Serum Vitamin C', imageUrl: '   '),
          ]),
        ),
      );
      await _openApiList(tester);

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.spa), findsNWidgets(2));
      expect(client.requestedUrls, isEmpty);
    });
  });

  testWidgets('Ảnh tải lỗi quay lại placeholder và không crash', (
    tester,
  ) async {
    final client = _FakeImageClient({_brokenImagePath: _brokenImage});

    await _withFakeImages(client, () async {
      await tester.pumpWidget(
        _app(
          _repository([
            _product(id: 104, name: 'Son Hỏng Ảnh', imageUrl: _brokenImageUrl),
          ]),
        ),
      );
      await _openApiList(tester);

      // errorBuilder đã thay ảnh bằng placeholder.
      expect(find.byIcon(Icons.spa), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(client.requestedUrls.map((url) => url.path), [_brokenImagePath]);
    });
  });

  testWidgets('Kích thước vùng ảnh giữ 48x48 khi loading và khi lỗi', (
    tester,
  ) async {
    final controller = StreamController<List<int>>();
    final client = _FakeImageClient({
      _okImagePath: () => _pendingImage(controller),
      _brokenImagePath: _brokenImage,
    });

    await _withFakeImages(client, () async {
      await tester.pumpWidget(
        _app(
          _repository([
            _product(id: 201, name: 'Son Đang Tải', imageUrl: _okImageUrl),
            _product(id: 202, name: 'Son Lỗi Ảnh', imageUrl: _brokenImageUrl),
          ]),
        ),
      );

      // Giữ ảnh thứ nhất ở trạng thái đang tải để đo trước khi ảnh về.
      await tester.tap(find.byType(Switch));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // Ảnh thứ nhất đang tải: spinner nhỏ, vùng ảnh vẫn 48x48.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final loadingThumbSize = tester.getSize(_thumbOf('Son Đang Tải'));
      final loadingCardSize = tester.getSize(_cardOf('Son Đang Tải'));
      expect(loadingThumbSize, const Size(48, 48));

      // Ảnh thứ hai lỗi ngay: về placeholder, vùng ảnh vẫn 48x48.
      expect(find.byIcon(Icons.spa), findsOneWidget);
      expect(tester.getSize(_thumbOf('Son Lỗi Ảnh')), const Size(48, 48));

      // Cho ảnh thứ nhất tải xong rồi so kích thước.
      controller.add(_tinyPng);
      await controller.close();
      await _waitForDecodedImages(tester, 1);

      // Ảnh thứ nhất đã vẽ, ảnh thứ hai vẫn là placeholder.
      expect(_decodedImageCount(tester), 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.spa), findsOneWidget);
      expect(tester.getSize(_thumbOf('Son Đang Tải')), const Size(48, 48));
      expect(tester.getSize(_thumbOf('Son Lỗi Ảnh')), const Size(48, 48));
      // Card giữ nguyên chiều cao dù ảnh chuyển từ loading sang ảnh thật.
      expect(
        tester.getSize(_cardOf('Son Đang Tải')).height,
        loadingCardSize.height,
      );
      // Card có ảnh lỗi cao bằng card có ảnh thật.
      expect(
        tester.getSize(_cardOf('Son Lỗi Ảnh')).height,
        loadingCardSize.height,
      );
    });
  });

  testWidgets('Danh sách sản phẩm không overflow trên màn hình điện thoại', (
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
        'Son Kem Lì Satin Đỏ Dưỡng Môi Siêu Mềm Phiên Bản Giới Hạn';

    await _withFakeImages(client, () async {
      await tester.pumpWidget(
        _app(
          _repository([
            _product(
              id: 301,
              name: longName,
              imageUrl: _okImageUrl,
              sku: 'KC-0001-RED-SATIN-LIMITED-2026',
            ),
            _product(
              id: 302,
              name: 'Kem Chống Nắng SPF 50+ Dưỡng Sáng Da',
              imageUrl: _brokenImageUrl,
              sku: 'KC-0003-SPF50',
            ),
          ]),
        ),
      );
      await _openApiList(tester);

      // Không có RenderFlex overflow: Flutter sẽ ghi lỗi vào test nếu tràn.
      expect(tester.takeException(), isNull);
      expect(find.text('2 sản phẩm'), findsOneWidget);
      expect(_decodedImageCount(tester), 0);
      // Ảnh thứ nhất còn đang tải, ảnh thứ hai lỗi nên về placeholder.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.spa), findsOneWidget);
      for (final name in [longName, 'Kem Chống Nắng SPF 50+ Dưỡng Sáng Da']) {
        expect(tester.getSize(_thumbOf(name)), const Size(48, 48));
      }

      controller.add(_tinyPng);
      await controller.close();
      await _waitForDecodedImages(tester, 1);

      expect(tester.takeException(), isNull);
      expect(_decodedImageCount(tester), 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.spa), findsOneWidget);
    });
  });
}
