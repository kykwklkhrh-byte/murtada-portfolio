enum VideoLinkKind { youtubeVideo, youtubeChannel, directMp4, unsupported }

VideoLinkKind classifyVideoLink(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
      uri.host.isEmpty) return VideoLinkKind.unsupported;
  final host = uri.host.toLowerCase();
  if (host == 'youtu.be' || host == 'www.youtu.be') {
    return uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty
        ? VideoLinkKind.youtubeVideo : VideoLinkKind.unsupported;
  }
  if (const {'youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com'}
      .contains(host)) {
    if (uri.path == '/watch' && uri.queryParameters['v']?.isNotEmpty == true) {
      return VideoLinkKind.youtubeVideo;
    }
    if (uri.pathSegments.length >= 2 &&
        const {'shorts', 'live', 'embed'}.contains(uri.pathSegments.first)) {
      return VideoLinkKind.youtubeVideo;
    }
    if (uri.pathSegments.isNotEmpty &&
        (uri.pathSegments.first.startsWith('@') ||
         const {'channel', 'c', 'user', 'playlist'}.contains(uri.pathSegments.first))) {
      return VideoLinkKind.youtubeChannel;
    }
    return VideoLinkKind.unsupported;
  }
  // Direct files only. No "YouTube download" bypass.
  if (uri.path.toLowerCase().endsWith('.mp4')) return VideoLinkKind.directMp4;
  return VideoLinkKind.unsupported;
}

String? parseTikTokHandle(String raw) {
  var handle = raw.trim();
  if (handle.startsWith('@')) handle = handle.substring(1);
  final url = Uri.tryParse(handle);
  if (url != null && url.hasScheme) {
    if (url.scheme != 'https' ||
        !const {'tiktok.com','www.tiktok.com','m.tiktok.com'}.contains(url.host.toLowerCase()) ||
        url.pathSegments.isEmpty || !url.pathSegments.first.startsWith('@')) return null;
    handle = url.pathSegments.first.substring(1);
  }
  if (!RegExp(r'^[A-Za-z0-9._]{2,24}$').hasMatch(handle)) return null;
  return handle.toLowerCase();
}
