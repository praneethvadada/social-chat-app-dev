# CALLS HISTORY SCREEN - VISUAL REFERENCE

## Current Implementation ✅

### Layout Structure

```
╔═══════════════════════════════════════════════════════════════╗
║                         CALLS                                 ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║  [Avatar]  John Doe                               ☎️          ║
║  ↗ Outgoing call • Today, 10:30 AM                          │
║  (GREEN arrow, normal text, AUDIO ICON at end)             │
║                                                             │
║  ────────────────────────────────────────────────────────  │
║                                                             │
║  [Avatar]  Sarah Johnson                          🎥         ║
║  ↙ Video call • Yesterday, 9:45 PM                         │
║  (BLUE arrow, normal text, VIDEO ICON at end)             │
║                                                             │
║  ────────────────────────────────────────────────────────  │
║                                                             │
║  [Avatar]  Mike Brown                             ☎️         ║
║  ↙ Missed audio call • Monday, 3:20 PM                     │
║  (RED arrow, RED TEXT, AUDIO ICON at end)                 │
║                                                             │
║  ────────────────────────────────────────────────────────  │
║                                                             │
║  [Avatar]  Emma Davis                             🎥         ║
║  ↗ Outgoing call • 15 January, 2:10 PM                     │
║  (GREEN arrow, normal text, VIDEO ICON at end)            │
║                                                             │
╚═══════════════════════════════════════════════════════════════╝
```

## Color Coding Reference

### 🟢 GREEN - Outgoing Calls
```
┌────────────────────────────────────────┐
│ [Avatar]  Contact Name        ☎️/🎥     │
│ ↗ Call type • Timestamp              │
│ • Arrow color: GREEN                  │
│ • Name color: Black/Normal            │
│ • Subtitle: Normal gray               │
│ • Type: ANY (missed or accepted)      │
└────────────────────────────────────────┘
```

### 🔵 BLUE - Incoming Calls (Accepted)
```
┌────────────────────────────────────────┐
│ [Avatar]  Contact Name        ☎️/🎥     │
│ ↙ Call type • Timestamp              │
│ • Arrow color: BLUE                   │
│ • Name color: Black/Normal            │
│ • Subtitle: Normal gray               │
│ • Status: NOT "Missed"                │
└────────────────────────────────────────┘
```

### 🔴 RED - Incoming Calls (Missed)
```
┌────────────────────────────────────────┐
│ [Avatar]  Contact Name        ☎️/🎥     │
│ ↙ Missed call • Timestamp            │
│ • Arrow color: RED                    │
│ • Name color: RED                     │
│ • Subtitle: Dark RED                  │
│ • Status: "Missed audio/video call"   │
└────────────────────────────────────────┘
```

## Arrow Icons Reference

- **Outgoing:** ↗ `Icons.call_made` (diagonal arrow pointing up-right)
- **Incoming:** ↙ `Icons.call_received` (diagonal arrow pointing down-left)

## Call Type Icons (at end of card)

- **Audio:** ☎️ `Icons.phone` (telephone receiver)
- **Video:** 🎥 `Icons.videocam` (video camera)

## Timestamp Formats

| Scenario | Time Difference | Format |
|----------|-----------------|--------|
| Just made | 0-59 seconds | "Just Now" |
| Few minutes ago | 1-59 minutes | "5 min ago" |
| Few hours ago | 1-23 hours | "Today, 2:30 PM" |
| Previous day | 24-48 hours | "Yesterday, 9:45 PM" |
| Recent week | 2-6 days | "Monday, 3:20 PM" |
| Older | 7+ days | "15 January, 2:10 PM" |

## Example Cards - Real Scenarios

### Example 1: Outgoing Audio Call
```
[👨 Avatar]  Alex Smith                                   ☎️
↗ Outgoing call • Today, 2:15 PM
```
- Arrow: 🟢 GREEN
- Text: Normal (black)
- Icon: ☎️ (phone)

### Example 2: Incoming Video Call (Accepted)
```
[👩 Avatar]  Lisa Johnson                               🎥
↙ Video call • Yesterday, 5:30 PM
```
- Arrow: 🔵 BLUE
- Text: Normal (black)
- Icon: 🎥 (videocam)

### Example 3: Incoming Audio Call (Missed)
```
[👨 Avatar]  Bob Wilson                                 ☎️
↙ Missed audio call • Monday, 10:00 AM
```
- Arrow: 🔴 RED
- Text: RED (both name and subtitle)
- Icon: ☎️ (phone)

### Example 4: Outgoing Video Call
```
[👩 Avatar]  Carol White                               🎥
↗ Outgoing call • 5 January, 6:45 PM
```
- Arrow: 🟢 GREEN
- Text: Normal (black)
- Icon: 🎥 (videocam)

## User Interaction

### Tap Card
```
User taps call card
        ↓
New call initiated with same user
        ↓
Uses same call type (audio/video)
        ↓
Call screen appears
```

### Pull to Refresh
```
Swipe down from top
        ↓
Loading spinner appears
        ↓
Fetches latest call history
        ↓
List updates with new calls
```

### Avatar Handling
```
If profile has picture:
    Show CircleAvatar with NetworkImage
    
If no picture:
    Show CircleAvatar with initials
    Example: "John Doe" → "JD"
    
If initials unavailable:
    Show first letter of user ID
    Example: userId=5 → "5"
```

## Call Flow - Immediate Logging

### During Call
```
Call Screen
    ↓
_callTimer starts/stops
    ↓
Duration calculated = elapsed time
```

### When User Hangs Up
```
User taps hang up
    ↓
_endCall() called
    ↓
Duration = _callTimer.elapsedMilliseconds / 1000
    ↓
updateCallEnded() called ⚡ IMMEDIATELY
    ↓
POST /calls/end with:
{
  "fromUserId": 1,
  "toUserId": 2,
  "channelName": "chat_1_2",
  "isVideo": true,
  "duration": 245,
  "status": "ended"
}
    ↓
CallStateManager transitions to 'ended'
    ↓
Wait 500ms for backend
    ↓
_refresh() fetches new history
    ↓
NEW CALL APPEARS ✅
```

## Responsive Design

### Portrait Mode (Default)
```
Width: Full screen
Padding: 12px horizontal
Avatar: 48px diameter
Font sizes:
  - Title: 15px
  - Subtitle: 13px
  - Icon: 20px
```

### Landscape Mode
```
Same layout, adapts to wider screen
Maintains proportions
Avatar remains 48px
```

## Loading States

### Initial Load
```
⏳ Circular progress indicator
Text: "Loading call history..."
```

### No Calls
```
Text: "No calls yet"
(empty state message)
```

### Error
```
Text: "Failed to load call history"
(error state with retry option)
```

## Timezone Example

**Database stores:** `2024-01-15T10:30:00Z` (UTC)

**Device timezone:** Asia/Kolkata (IST = UTC+5:30)

**Displayed as:** `Today, 4:00 PM` (converted to local time)

---

## Implementation Checklist

- ✅ Username from profile
- ✅ Audio/Video icons at end
- ✅ Incoming/Outgoing arrows
- ✅ Color-coded by type
- ✅ WhatsApp-style timestamps
- ✅ Indian timezone support
- ✅ Immediate logging on call end
- ✅ Auto-refresh after 500ms
- ✅ Avatar display
- ✅ Tap to call
- ✅ Pull to refresh
- ✅ Error handling
- ✅ Loading states

---

**Status: READY FOR PRODUCTION ✅**
