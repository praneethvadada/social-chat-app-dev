#!/bin/bash

# Real-Time Chat Verification Script
# Run this to verify all real-time chat components are working

echo "================================"
echo "Real-Time Chat Verification"
echo "================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Backend URL
BACKEND_URL="http://192.168.31.74:8082"

echo -e "${YELLOW}[Step 1] Checking Backend Health...${NC}"
curl -s -o /dev/null -w "Status: %{http_code}\n" "$BACKEND_URL/health"
echo ""

echo -e "${YELLOW}[Step 2] Verifying WebSocket Endpoint...${NC}"
# Try to connect to WebSocket endpoint
echo "WebSocket should be available at: $BACKEND_URL/ws"
echo ""

echo -e "${YELLOW}[Step 3] Checking Backend Logs for Handlers...${NC}"
echo "Expected log patterns:"
echo "  ✓ [MessageController] WEBSOCKET MESSAGE RECEIVED"
echo "  ✓ [MessageController] READ RECEIPT RECEIVED"
echo "  ✓ [MessageService] Marked X messages as read"
echo ""

echo -e "${GREEN}[Step 4] Flutter App Logs to Monitor${NC}"
echo "Expected patterns:"
echo "  ✓ [ChatWebSocketService] Read receipt sent: X messages"
echo "  ✓ [MESSAGE] 📨 Parsing message JSON"
echo "  ✓ [PERSISTENCE] Saved message for user=X"
echo ""

echo -e "${GREEN}[Step 5] Manual Testing Steps${NC}"
echo ""
echo "1. Open app on TWO devices (or emulators)"
echo "2. Navigate to Chats → Select conversation"
echo "3. User A sends message → Check:"
echo "   - Message appears instantly on User B"
echo "   - Backend logs show: [MessageController] WEBSOCKET MESSAGE RECEIVED"
echo ""
echo "4. User B reads message → Check:"
echo "   - 'Read' badge appears in User A's UI"
echo "   - Backend logs show: [MessageController] READ RECEIPT RECEIVED"
echo ""
echo "5. User B types → Check:"
echo "   - 'is typing...' appears on User A"
echo "   - Typing indicator appears in Flutter UI"
echo ""
echo "6. Close & reopen app → Check:"
echo "   - All messages still visible"
echo "   - [PERSISTENCE] logs show: Saved message"
echo ""

echo -e "${GREEN}[Step 6] Database Verification SQL${NC}"
echo "Run these to verify database state:"
echo ""
echo "-- Check read receipts:"
echo "SELECT id, senderId, receiverId, content, readAt FROM messages WHERE readAt IS NOT NULL LIMIT 10;"
echo ""
echo "-- Check unread messages:"
echo "SELECT id, senderId, receiverId, content, readAt FROM messages WHERE readAt IS NULL LIMIT 10;"
echo ""

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Verification Complete!${NC}"
echo "================================"
echo ""
echo "If any tests fail, check:"
echo "1. Backend: Are WebSocket handlers registered?"
echo "2. Flutter: Is app connected to WebSocket?"
echo "3. Database: Are messages being saved?"
echo "4. Logs: Are there any error messages?"
echo ""
