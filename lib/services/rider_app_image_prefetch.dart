import 'dart:async';

import '../utils/app_image_cache.dart';
import '../utils/shop_image_resolver.dart';

/// Warms rider order thumbnails on disk so repeat views load instantly.
class RiderAppImagePrefetch {
  RiderAppImagePrefetch._();

  static final Set<String> _completedUrls = <String>{};
  static final Set<String> _inFlight = <String>{};

  static void scheduleOrderCardImages(
    Map<String, dynamic> orderData, {
    String? shopImageUrl,
  }) {
    final urls = _collectOrderImageUrls(
      orderData,
      shopImageUrl: shopImageUrl,
    );
    unawaited(prefetchUrls(urls));
  }

  static List<String> _collectOrderImageUrls(
    Map<String, dynamic> orderData, {
    String? shopImageUrl,
  }) {
    final seen = <String>{};
    final urls = <String>[];

    void add(String? raw) {
      final url = raw?.trim();
      if (url == null || url.isEmpty || !seen.add(url)) {
        return;
      }
      urls.add(url);
    }

    add(shopImageUrl);
    add(ShopImageResolver.readFromOrder(orderData));

    final rawProducts = orderData['products'];
    if (rawProducts is List) {
      for (final item in rawProducts) {
        if (item is! Map) {
          continue;
        }
        add(
          ShopImageResolver.readProductImageUrl(
            item,
            fallbackShopImageUrl: shopImageUrl,
          ),
        );
      }
    }

    return urls;
  }

  static Future<void> prefetchUrls(List<String> urls) async {
    if (urls.isEmpty) {
      return;
    }

    final pending = urls
        .where(
          (url) =>
              url.isNotEmpty &&
              !_completedUrls.contains(url) &&
              !_inFlight.contains(url),
        )
        .toList(growable: false);
    if (pending.isEmpty) {
      return;
    }

    for (final url in pending) {
      await _prefetchUrl(url);
    }
  }

  static Future<void> _prefetchUrl(String url) async {
    if (_completedUrls.contains(url) || _inFlight.contains(url)) {
      return;
    }
    _inFlight.add(url);
    try {
      if (await isAppImageCached(url)) {
        _completedUrls.add(url);
        return;
      }
      final fileInfo = await AppImageDownloadCoordinator.run(
        () => AppImageCacheManager.instance.downloadFile(url),
      );
      AppImageDiskHintCache.remember(url, fileInfo.file);
      _completedUrls.add(url);
    } catch (_) {
      // CachedAppImage will retry on demand.
    } finally {
      _inFlight.remove(url);
    }
  }
}
