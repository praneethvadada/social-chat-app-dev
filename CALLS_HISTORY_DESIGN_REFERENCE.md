# Call History Screen - Visual Design Reference

## Layout Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                           Calls                                 │
│ ═════════════════════════════════════════════════════════════════│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  [Avatar]  John Smith        🎥 (video call icon)       │    │
│  │            ↗ Missed video call • Today, 2:30 PM        │    │
│  │ ═────────────────────────────────────────────────────────│    │
│  │  [Avatar]  Sarah Johnson     ☎️  (audio call icon)      │    │
│  │            ↙ Audio call • Yesterday, 9:45 PM           │    │
│  │ ═────────────────────────────────────────────────────────│    │
│  │  [Avatar]  Mike Brown        🎥 (video call icon)       │    │
│  │            ↙ Missed video call • Monday, 3:20 PM       │    │
│  │ ═────────────────────────────────────────────────────────│    │
│  │  [Avatar]  Emma Davis        ☎️  (audio call icon)      │    │
│  │            ↗ Audio call • 15 January, 2:10 PM          │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Color Coding Examples

### Example 1: Outgoing Call (Green)
```
┌──────────────────────────────────────────┐
│ [Avatar]  Alice Wilson        🎥          │
│ ↗ Video call • Today, 10:00 AM           │
│ • Arrow color: 🟢 GREEN                  │
│ • Name color: Normal (black/dark)        │
│ • Icon: ↗ (call_made)                    │
│ • Call type: 🎥 (video)                  │
└──────────────────────────────────────────┘
```

### Example 2: Received Call (Blue)
```
┌──────────────────────────────────────────┐
│ [Avatar]  Bob Thompson         ☎️          │
│ ↙ Audio call • Yesterday, 5:30 PM        │
│ • Arrow color: 🔵 BLUE                   │
│ • Name color: Normal (black/dark)        │
│ • Icon: ↙ (call_received)                │
│ • Call type: ☎️ (audio)                  │
└──────────────────────────────────────────┘
```

### Example 3: Missed Call (Red)
```
┌──────────────────────────────────────────┐
│ [Avatar]  Carol White          🎥          │
│ ↙ Missed video call • Monday, 7:15 PM    │
│ • Arrow color: 🔴 RED                    │
│ • Name color: RED                        │
│ • Subtitle color: Dark RED               │
│ • Icon: ↙ (call_received)                │
│ • Call type: 🎥 (video)                  │
│ • Status: "Missed" highlighted in text   │
└──────────────────────────────────────────┘
```

## Timestamp Format Examples

| Scenario | Backend Timestamp | Device Timezone | Display Format |
|----------|-------------------|-----------------|----------------|
| Just now | 2024-01-15 10:30 (UTC) | IST (UTC+5:30) | "Just Now" |
| 5 min ago | 2024-01-15 10:30 (UTC) | IST | "5 min ago" |
| 2 hours ago | 2024-01-15 10:30 (UTC) | IST | "2 hours ago" |
| Same day, 2pm | 2024-01-15 14:00 (UTC) | IST | "Today, 7:30 PM" |
| Yesterday, 4pm | 2024-01-14 16:00 (UTC) | IST | "Yesterday, 9:30 PM" |
| 3 days ago | 2024-01-12 10:00 (UTC) | IST | "Friday, 3:30 PM" |
| Older | 2024-01-01 10:00 (UTC) | IST | "1 January, 3:30 PM" |

## Call Type Icons

- **Audio Call**: ☎️ `Icons.phone` (receiver)
- **Video Call**: 🎥 `Icons.videocam` (camera)

*Position*: Right side (trailing) of each card

## Direction Icons

- **Outgoing**: ↗ `Icons.call_made` (diagonal arrow up-right)
- **Incoming**: ↙ `Icons.call_received` (diagonal arrow down-left)

*Position*: Left side of subtitle, before call label

## Call Labels

| Scenario | Label |
|----------|-------|
| Outgoing audio | "Audio call" |
| Outgoing video | "Video call" |
| Received audio (accepted) | "Audio call" |
| Received video (accepted) | "Video call" |
| Missed audio call | "Missed audio call" |
| Missed video call | "Missed video call" |

## Avatar Display

```
┌─────────────────────┐
│ If profile picture: │
│ ┌─────────────────┐ │
│ │   [Image]       │ │
│ │  CircleAvatar   │ │
│ │  Radius: 24px   │ │
│ └─────────────────┘ │
│                     │
│ If no picture:      │
│ ┌─────────────────┐ │
│ │  JD             │ │
│ │  (Initials)     │ │
│ │  Radius: 24px   │ │
│ └─────────────────┘ │
└─────────────────────┘
```

## Interaction

### Tapping a Card
- Initiates a **new call** with the same user
- Uses the **same call type** as the last call (audio if was audio, video if was video)
- Navigates to call screen if user is available

### Pull-to-Refresh
- Refreshes call history from backend
- Shows loading spinner while fetching
- Preserves scroll position if possible

## State Indicators

### Loading State
```
┌─────────────────────┐
│                     │
│   ⏳ Loading...      │
│   (Spinner)         │
│                     │
└─────────────────────┘
```

### Empty State
```
┌─────────────────────┐
│                     │
│   No calls yet      │
│                     │
└─────────────────────┘
```

### Error State
```
┌─────────────────────┐
│                     │
│  Failed to load     │
│  call history       │
│                     │
└─────────────────────┘
```

## Code Color Mapping

```dart
// Outgoing (Green)
directionColor = Colors.green        // #4CAF50

// Received (Blue)
directionColor = Colors.blue         // #2196F3

// Missed (Red)
directionColor = Colors.red          // #F44336
missedNameColor = Colors.red         // #F44336
missedSubtitleColor = Colors.red.shade600  // #E53935
```

## Responsive Design

- **Portrait Mode**: Full-width cards with proper spacing
- **Landscape Mode**: Adapts to wider screen with same proportions
- **Padding**: 
  - Horizontal: 12px (card padding), 8px (list padding)
  - Vertical: 4px (card padding), 8px (list padding)
- **Divider**: Full-width with 12px indent/end indent

## Animation

- Smooth fade-in of avatar as image loads
- Spinner animation during load
- RefreshIndicator pull-to-refresh animation
- ListTile tap animation (if applicable)

## Accessibility

- Avatar has color contrast with background
- Icons are clearly visible in colors
- Text sizes are readable (13-15px for subtitle/title)
- Names are bold for better readability
- Timestamp is slightly grayed out for visual hierarchy

---

**Note**: All colors, sizes, and formats can be customized in `calls_screen.dart` and `timestamp_parser.dart` based on your design system preferences.
