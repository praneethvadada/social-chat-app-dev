# CALLS HISTORY SCREEN - EXACT COLOR & LAYOUT REFERENCE

## Color Codes (Exact)

### 🟢 GREEN (Outgoing Calls)
```
Material Color: Colors.green
Hex: #4CAF50
RGB: rgb(76, 175, 80)
Used for: Arrow icon on outgoing calls
```

### 🔵 BLUE (Received Calls)
```
Material Color: Colors.blue
Hex: #2196F3
RGB: rgb(33, 150, 243)
Used for: Arrow icon on received/accepted calls
```

### 🔴 RED (Missed Calls)
```
Material Color: Colors.red (for arrow)
           Colors.red.shade600 (for text)
Hex: #F44336 (arrow)
     #E53935 (text)
Used for: Arrow, name, and subtitle text on missed calls
```

---

## Layout Breakdown

```
┌─────────────────────────────────────────────────────────────┐
│                       CALLS HEADER                          │
│  Primary Color: Theme.colorScheme.primary                  │
│  Size: 26pt, FontWeight: w800                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    CALL HISTORY ITEM                        │
│                                                              │
│  [Avatar]  Username                               [Icon]    │
│  48×48px   15pt bold                                20×20px  │
│  
│  ↗/↙ Call Label • Timestamp                                │
│  16pt  13pt normal           13pt gray                     │
│  COLOR CODED                                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Component Details

### Avatar (Leading)
```
Type: CircleAvatar
Size: 48×48px (radius 24)

If has picture:
  - backgroundImage: NetworkImage(profilePictureUrl)
  - Shows actual profile photo
  
If no picture:
  - Shows initials (JD for John Doe)
  - backgroundColor: Theme color
  - Text: 15pt bold white
```

### Arrow Icon (Subtitle Left)
```
Type: Icon
Size: 16px
Colors:
  - GREEN if isOutgoing
  - BLUE if isIncoming && !isMissed
  - RED if isIncoming && isMissed

Icons:
  - Outgoing: Icons.call_made (↗ arrow)
  - Incoming: Icons.call_received (↙ arrow)
```

### Title (Username)
```
Type: Text
Size: 15pt
FontWeight: w600 (semi-bold)
MaxLines: 1
Overflow: TextOverflow.ellipsis

Color:
  - BLACK/DARK if NOT missed
  - RED if missed (Colors.red)
  
Source: profile?.fullName ?? profile?.username ?? 'User $userId'
```

### Subtitle (Call Label + Timestamp)
```
Layout: Row
  ├─ Icon (arrow)
  ├─ SizedBox(6dp)
  ├─ Expanded(
      Child: Text(..., overflow.ellipsis)
    )

Text Format: "[Call Label] • [Timestamp]"
  Example: "Missed audio call • Today, 2:30 PM"
  Example: "Video call • 5 min ago"
  
Size: 13pt
Color:
  - GRAY[600] if NOT missed
  - RED.shade600 (#E53935) if missed
```

### Call Type Icon (Trailing)
```
Type: Icon with Padding
Size: 20px
Padding: EdgeInsets.only(right: 8)
Color: Theme.colorScheme.primary

Icons:
  - Audio: Icons.phone (☎️ receiver icon)
  - Video: Icons.videocam (🎥 camera icon)
```

---

## Complete Card Structure

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ListTile(                                                   │
│    contentPadding: 12px horizontal, 4px vertical            │
│    leading: CircleAvatar(48×48)  ← Avatar                   │
│    title: Text(username)        ← Bold name (15pt)          │
│    subtitle: Row(                                            │
│      ├─ Icon(arrow)             ← GREEN/BLUE/RED (16pt)    │
│      ├─ SizedBox(6px)                                        │
│      └─ Expanded(Text(...))     ← Label + timestamp (13pt)  │
│    )                                                         │
│    trailing: Icon(callType)     ← ☎️/🎥 (20pt)              │
│    onTap: () => _startCall()    ← Tap to call               │
│  )                                                           │
│                                                              │
│  Divider(height: 1, indent: 12, endIndent: 12)             │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Call Label Variations

### Outgoing Call
```
"Outgoing call"        ← Basic
"Audio call"           ← When type known
"Video call"           ← When type known
```

### Incoming - Accepted
```
"Audio call"           ← Audio type
"Video call"           ← Video type
```

### Incoming - Missed
```
"Missed audio call"    ← Audio type (RED)
"Missed video call"    ← Video type (RED)
```

---

## Timestamp Examples with Exact Format

### WhatsApp Style Format

```
formatWhatsAppStyle(DateTime timestamp) {
  // Converts UTC to local, then formats:
  
  if (< 60 seconds):
    return "Just Now"
    
  if (< 60 minutes):
    return "${minutes} min ago"
    Example: "5 min ago"
    
  if (same day):
    return "Today, ${h:mm a}"
    Example: "Today, 2:30 PM"
    
  if (yesterday):
    return "Yesterday, ${h:mm a}"
    Example: "Yesterday, 9:45 PM"
    
  if (< 6 days):
    return "${EEEE}, ${h:mm a}"
    Example: "Monday, 3:20 PM"
    
  else:
    return "${d MMMM}, ${h:mm a}"
    Example: "15 January, 2:10 PM"
}
```

---

## Color Summary Table

| Component | Outgoing | Received (OK) | Received (Miss) |
|-----------|----------|---------------|-----------------|
| Arrow | 🟢 GREEN | 🔵 BLUE | 🔴 RED |
| Name | Black | Black | 🔴 RED |
| Label | Normal | Normal | 🔴 RED |
| Timestamp | Gray | Gray | 🔴 RED |
| Icon | Black | Black | 🔴 RED |

---

## Spacing Reference

```
┌─────────────────────────────────────────────────────┐
│  Padding: 8px (horizontal), 8px (vertical)          │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │ Padding: 12px (h), 4px (v)                   │   │
│  │                                              │   │
│  │ [Avatar] Name                            [Icon] │   │
│  │ 48×48px                                  20×20px │   │
│  │ Gap: 12px                                       │   │
│  │                                              │   │
│  │ ↗ Label • Timestamp                            │   │
│  │ 16pt   Gap: 6px  13pt                          │   │
│  │                                              │   │
│  └──────────────────────────────────────────────┘   │
│  Divider (12px indent on both sides)                │
│  Height: 1px                                        │
└─────────────────────────────────────────────────────┘
```

---

## Screenshot Reference (ASCII)

### Outgoing Call
```
╔════════════════════════════════════════════════════════╗
║ 👨 John Doe                                      ☎️   ║
║ ↗ Outgoing call • Just Now                           ║
║ (GREEN arrow, black text, phone icon)               ║
╚════════════════════════════════════════════════════════╝
```

### Received Call (Accepted)
```
╔════════════════════════════════════════════════════════╗
║ 👩 Sarah Johnson                                   🎥 ║
║ ↙ Video call • Yesterday, 9:45 PM                   ║
║ (BLUE arrow, black text, video icon)               ║
╚════════════════════════════════════════════════════════╝
```

### Received Call (Missed)
```
╔════════════════════════════════════════════════════════╗
║ 👨 Mike Brown                                      ☎️ ║
║ ↙ Missed audio call • Monday, 3:20 PM              ║
║ (RED arrow, RED text, phone icon)                  ║
╚════════════════════════════════════════════════════════╝
```

---

## Font Metrics

| Component | Size | Weight | Color |
|-----------|------|--------|-------|
| Header | 26pt | w800 | Primary |
| Username | 15pt | w600 | BLACK or RED |
| Call Label | 13pt | normal | GRAY or RED |
| Timestamp | 13pt | normal | GRAY or RED |
| Arrow | 16pt | (icon) | GREEN/BLUE/RED |
| Call Icon | 20pt | (icon) | Primary |

---

## Color Conversion Guide

### If You Need Different Colors

**To change outgoing call color:**
```dart
// Find this line in calls_screen.dart
directionColor = Colors.green;

// Change to:
directionColor = Colors.teal; // or any color
```

**To change received call color:**
```dart
// Find this line
directionColor = Colors.blue;

// Change to:
directionColor = Colors.cyan; // or any color
```

**To change missed call color:**
```dart
// Find this line
directionColor = Colors.red;

// Change to:
directionColor = Colors.orange; // or any color
```

---

## Responsive Behavior

### On Different Screen Sizes

```
Phone (360px):      Normal layout, full width minus padding
Tablet (600px):     Same layout, scales proportionally
Landscape:          Same layout, adapts to width
```

### Avatar Scaling
```
Always: 48×48px (radius 24)
Does NOT scale with screen size
Maintains consistency across devices
```

### Text Scaling
```
Follows Material Design guidelines
Font sizes fixed, not scaled
Readable on all devices
```

---

## Animation & Interaction

### On Tap
```
ListTile default tap animation
Slight color change to indicate interactive
Ripple effect on press
Calls _startCall() with same user
```

### Loading State
```
CircularProgressIndicator
Centered on screen
Shows while fetching history
```

### Error State
```
Red error text
"Failed to load call history"
Retry implied via pull-to-refresh
```

---

**Ready to implement!** 🎨
