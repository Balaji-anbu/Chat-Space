class EmojiUtils {
  // Regular expression to match emoji characters
  static final RegExp _emojiRegex = RegExp(
    r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{1F900}-\u{1F9FF}]|[\u{1F018}-\u{1F270}]|[\u{238C}-\u{2454}]|[\u{20D0}-\u{20FF}]|[\u{FE00}-\u{FE0F}]|[\u{1F000}-\u{1F02F}]|[\u{1F0A0}-\u{1F0FF}]|[\u{1F100}-\u{1F64F}]|[\u{1F680}-\u{1F6FF}]|[\u{1F910}-\u{1F96B}]|[\u{1F980}-\u{1F9E0}]',
    unicode: true,
  );

  // Check if text contains only emojis
  static bool isEmojiOnly(String text) {
    if (text.trim().isEmpty) return false;

    // Remove all emoji characters from the text
    final textWithoutEmojis = text.replaceAll(_emojiRegex, '').trim();

    // If there's no text left after removing emojis, it's emoji-only
    return textWithoutEmojis.isEmpty;
  }

  // Get emoji count in text
  static int getEmojiCount(String text) {
    return _emojiRegex.allMatches(text).length;
  }

  // Check if text is a single emoji
  static bool isSingleEmoji(String text) {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return false;

    // Check if it's exactly one emoji character
    final matches = _emojiRegex.allMatches(trimmedText);
    if (matches.length != 1) return false;

    // Check if the emoji is the only content (no other characters)
    final textWithoutEmojis = trimmedText.replaceAll(_emojiRegex, '').trim();
    return textWithoutEmojis.isEmpty;
  }

  // Get appropriate font size for emoji display
  static double getEmojiFontSize(String text, {double baseSize = 16.0}) {
    final emojiCount = getEmojiCount(text);

    if (emojiCount == 1) {
      return baseSize * 2.5; // Single emoji gets larger size
    } else if (emojiCount <= 3) {
      return baseSize * 1.8; // 2-3 emojis get medium size
    } else {
      return baseSize * 1.2; // More emojis get smaller size
    }
  }
}
