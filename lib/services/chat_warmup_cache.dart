class CachedRiderChatMessage {
  const CachedRiderChatMessage({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, dynamic> data;
}

class _CacheEntry<T> {
  _CacheEntry(this.value, this.cachedAt);

  final T value;
  final DateTime cachedAt;

  bool isFresh(Duration ttl) => DateTime.now().difference(cachedAt) <= ttl;
}

/// In-memory cache for rider chat messages and peer phone numbers.
class ChatWarmupCache {
  ChatWarmupCache._();

  static final ChatWarmupCache instance = ChatWarmupCache._();

  static const Duration messageTtl = Duration(minutes: 3);
  static const Duration phoneTtl = Duration(minutes: 10);

  final Map<String, _CacheEntry<List<CachedRiderChatMessage>>> _messages =
      <String, _CacheEntry<List<CachedRiderChatMessage>>>{};
  final Map<String, _CacheEntry<String>> _phones =
      <String, _CacheEntry<String>>{};

  List<CachedRiderChatMessage>? peekMessages(String chatId) {
    final entry = _messages[chatId];
    if (entry == null || !entry.isFresh(messageTtl)) {
      return null;
    }
    return List<CachedRiderChatMessage>.from(entry.value);
  }

  void putMessages(String chatId, List<CachedRiderChatMessage> messages) {
    _messages[chatId] = _CacheEntry<List<CachedRiderChatMessage>>(
      List<CachedRiderChatMessage>.from(messages),
      DateTime.now(),
    );
  }

  String? peekPhone(String peerUid) {
    final entry = _phones[peerUid];
    if (entry == null || !entry.isFresh(phoneTtl)) {
      return null;
    }
    return entry.value;
  }

  void cachePhone(String peerUid, String phone) {
    if (peerUid.trim().isEmpty || phone.trim().isEmpty) {
      return;
    }
    _phones[peerUid] = _CacheEntry<String>(phone, DateTime.now());
  }
}
