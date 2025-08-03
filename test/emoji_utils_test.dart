import 'package:chatapp/core/utils/emoji_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmojiUtils Tests', () {
    test('should detect single emoji', () {
      expect(EmojiUtils.isEmojiOnly('😀'), true);
      expect(EmojiUtils.isEmojiOnly('❤️'), true);
      expect(EmojiUtils.isEmojiOnly('👍'), true);
    });

    test('should detect multiple emojis', () {
      expect(EmojiUtils.isEmojiOnly('😀❤️👍'), true);
      expect(EmojiUtils.isEmojiOnly('🎉🎊🎈'), true);
    });

    test('should not detect text as emoji', () {
      expect(EmojiUtils.isEmojiOnly('Hello'), false);
      expect(EmojiUtils.isEmojiOnly('Hello 😀'), false);
      expect(EmojiUtils.isEmojiOnly('😀 Hello'), false);
    });

    test('should handle empty string', () {
      expect(EmojiUtils.isEmojiOnly(''), false);
      expect(EmojiUtils.isEmojiOnly('   '), false);
    });

    test('should detect single emoji correctly', () {
      expect(EmojiUtils.isSingleEmoji('😀'), true);
      expect(EmojiUtils.isSingleEmoji('❤️'), true);
      expect(EmojiUtils.isSingleEmoji('😀❤️'), false);
      expect(EmojiUtils.isSingleEmoji('Hello'), false);
    });

    test('should count emojis correctly', () {
      expect(EmojiUtils.getEmojiCount('😀'), 1);
      expect(EmojiUtils.getEmojiCount('😀❤️👍'), 3);
      expect(EmojiUtils.getEmojiCount('Hello 😀'), 1);
      expect(EmojiUtils.getEmojiCount('Hello'), 0);
    });

    test('should return appropriate font sizes', () {
      expect(EmojiUtils.getEmojiFontSize('😀'), 40.0); // Single emoji
      expect(EmojiUtils.getEmojiFontSize('😀❤️'), 28.8); // 2 emojis
      expect(EmojiUtils.getEmojiFontSize('😀❤️👍🎉'), 19.2); // 4 emojis
    });
  });
}
