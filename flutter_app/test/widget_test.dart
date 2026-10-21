import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viral_clips_ai/main.dart';
import 'package:viral_clips_ai/source_tools.dart';

void main() {
  testWidgets('Laqta launches with real navigation, no server settings', (tester) async {
    await tester.pumpWidget(const ViralApp());
    expect(find.text('LAQTA • لَقطة'), findsOneWidget);
    expect(find.text('اختيار فيديو من الجهاز'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('يوتيوب'), findsOneWidget);
    expect(find.text('تيك توك'), findsOneWidget);
  });

  testWidgets('YouTube section exposes link input', (tester) async {
    await tester.pumpWidget(const ViralApp());
    await tester.tap(find.text('يوتيوب').last);
    await tester.pump();
    expect(find.text('رابط يوتيوب أو MP4 مباشر'), findsOneWidget);
    expect(find.text('فحص الرابط وإضافته'), findsOneWidget);
  });

  testWidgets('TikTok section exposes profile management', (tester) async {
    await tester.pumpWidget(const ViralApp());
    await tester.tap(find.text('تيك توك').last);
    await tester.pump();
    expect(find.text('إضافة الحساب إلى قائمتي'), findsOneWidget);
    expect(find.text('اسم الحساب أو رابط TikTok'), findsOneWidget);
    expect(find.textContaining('مو ربط رسمي'), findsOneWidget);
  });

  test('YouTube URL recognition validates exact hosts', () {
    expect(classifyVideoLink('https://youtu.be/abc123'), VideoLinkKind.youtubeVideo);
    expect(classifyVideoLink('https://www.youtube.com/watch?v=abc'), VideoLinkKind.youtubeVideo);
    expect(classifyVideoLink('https://youtube.com/shorts/abc'), VideoLinkKind.youtubeVideo);
    expect(classifyVideoLink('https://www.youtube.com/@channel'), VideoLinkKind.youtubeChannel);
    expect(classifyVideoLink('https://youtube.com.evil.com/watch?v=abc'), VideoLinkKind.unsupported);
    expect(classifyVideoLink('http://youtube.com/watch?v=abc'), VideoLinkKind.unsupported);
    expect(classifyVideoLink('https://example.com/movie.mp4'), VideoLinkKind.directMp4);
    expect(classifyVideoLink('https://example.com/movie.txt'), VideoLinkKind.unsupported);
  });

  test('TikTok handle normalization protects against fake domains', () {
    expect(parseTikTokHandle('@hello_24'), 'hello_24');
    expect(parseTikTokHandle('https://www.tiktok.com/@Demo.Me'), 'demo.me');
    expect(parseTikTokHandle('https://tiktok.com.evil.com/@victim'), null);
    expect(parseTikTokHandle('http://tiktok.com/@demo'), null);
    expect(parseTikTokHandle('bad/handle'), null);
    expect(parseTikTokHandle(''), null);
  });
}
