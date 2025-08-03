# Reply Functionality

This document describes the reply functionality that has been added to the chat app, similar to Instagram's reply feature.

## Features

### 1. Reply to Messages

- Users can reply to any message (both sent and received)
- **Slide right on any message** to reply (Instagram-style gesture)
- Reply mode shows a preview of the original message

### 2. Reply UI

- Reply mode displays a blue banner above the input field
- Shows the name of the person being replied to
- Displays a preview of the original message text
- Easy to cancel reply mode with the close button

### 3. Message Display

- Messages that are replies show a reply preview
- Reply preview includes:
  - Reply icon
  - Name of the original sender
  - Preview of the original message text
  - Left border to indicate it's a reply

### 4. Database Structure

- Messages now include a `replyTo` field that stores the ID of the message being replied to
- Backward compatible - existing messages without replies work normally

## Implementation Details

### MessageModel Updates

- Added `replyTo` field to store the ID of the replied message
- Added `replyToMessage` field for the actual message object (optional)
- Updated `fromMap`, `toMap`, and `copyWith` methods

### ChatService Updates

- Updated `sendMessage` method to accept optional `replyTo` parameter
- Updated message parsing to include reply information
- Maintains backward compatibility

### UI Updates

- Added slide-to-reply gesture (Instagram-style)
- Added reply mode state management
- Added reply preview UI in message bubbles
- Updated message options to include reply for all messages
- Added reply mode input field with preview

## Usage

1. **To reply to a message:**

   - **Slide right on any message** (Instagram-style gesture)
   - Type your reply message
   - Send the message

2. **To cancel a reply:**

   - Tap the close button (X) in the reply banner
   - Or send the reply message

3. **To view replies:**
   - Messages that are replies show a preview of the original message
   - The preview includes the sender's name and message text

## Technical Notes

- Reply functionality works for both sent and received messages
- **Slide-to-reply gesture** works in both directions (left-to-right swipe)
- Reply previews are limited to 2 lines with ellipsis for longer messages
- The reply system is fully integrated with the existing message system
- All existing features (reactions, editing, etc.) continue to work with replies
