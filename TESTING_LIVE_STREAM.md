# Testing Live Stream Features

## ⚠️ Important: Emulator vs Physical Device

### **Android Emulator Limitations:**
- ❌ **Camera won't work** - Emulators don't have real camera access
- ✅ **UI elements can be tested** - Stop button, live indicator, score overlay rendering
- ✅ **Navigation and flow** - Can test app navigation
- ❌ **Actual streaming** - Won't work without real camera

### **Physical Android Device (Recommended):**
- ✅ **Full functionality** - Camera, streaming, overlay all work
- ✅ **Real-world testing** - Actual RTMP streaming to YouTube
- ✅ **Performance testing** - Real device performance

---

## 🧪 Testing Options

### **Option 1: Test UI in Emulator (Quick Check)**

You can test the UI elements without actual streaming:

1. **Run the app on emulator:**
   ```bash
   cd flutter_app
   flutter run -d emulator-5554
   ```

2. **Navigate to Go Live screen:**
   - From the app, navigate to a match
   - Or use the router directly (you'll need a matchId)
   - The screen will show but camera won't initialize

3. **What you can test:**
   - ✅ UI layout and buttons
   - ✅ Stop button visibility (when `_isStreaming = true`)
   - ✅ Live indicator animation
   - ✅ Score overlay rendering (if you mock data)

---

### **Option 2: Test on Physical Device (Full Testing)**

**Best for complete testing:**

1. **Connect your Android phone via USB:**
   ```bash
   # Enable USB debugging on your phone
   # Then check devices:
   flutter devices
   ```

2. **Run on physical device:**
   ```bash
   cd flutter_app
   flutter run -d <your-device-id>
   ```

3. **Navigate to Go Live:**
   - Create a match first (or use existing match)
   - Navigate to `/go-live` route with match details
   - Or find the "Go Live" button in your match detail page

---

## 📱 Step-by-Step Testing Guide

### **Step 1: Start a Match**

You need a match to go live. Options:

**Option A: Create a new match**
- Navigate to "Create Match" screen
- Fill in team names, overs, etc.
- Create the match

**Option B: Use existing match**
- Find an existing match in your app
- Get the `matchId` from the match

### **Step 2: Navigate to Go Live Screen**

**From code (for testing):**
```dart
context.push(
  '/go-live',
  extra: {
    'matchId': 'your-match-id-here',
    'matchTitle': 'Team A vs Team B',
    'isDraft': false,
  },
);
```

**From UI:**
- Look for "Go Live" button in match detail page
- Or from scorecard page if there's a live stream option

### **Step 3: Test Live Streaming**

1. **Start Stream:**
   - Tap "GO LIVE" button
   - Grant camera permissions if prompted
   - Wait for stream to initialize

2. **Verify UI Elements:**
   - ✅ **Stop Button** - Should appear in top-left corner (red, with "STOP" text)
   - ✅ **Live Indicator** - Should appear in top-right (animated pulsing red "LIVE")
   - ✅ **Score Overlay** - Should appear at bottom showing match scores

3. **Test Score Updates:**
   - Open scorecard page in another tab/window (or on another device)
   - Update scores (add runs, wickets, etc.)
   - **Expected:** Score overlay on live stream should update within 2-3 seconds

4. **Test Stop Functionality:**
   - Tap the "STOP" button in top-left
   - Or tap "STOP STREAMING" button at bottom
   - Stream should stop and you should be navigated back

---

## 🎯 What to Test Specifically

### **1. Stop Button Visibility**
- [ ] Stop button appears in top-left when streaming starts
- [ ] Button is always visible (not hidden)
- [ ] Button is easily tappable
- [ ] Button stops the stream when tapped

### **2. Live Indicator**
- [ ] "LIVE" indicator appears in top-right
- [ ] Indicator has pulsing animation
- [ ] Indicator is clearly visible

### **3. Score Overlay**
- [ ] Overlay appears at bottom of screen
- [ ] Overlay shows current scores
- [ ] Overlay updates when scores change in scorecard
- [ ] Overlay is visible on the stream (check YouTube)

### **4. Score Updates**
- [ ] Open scorecard page
- [ ] Update a score (add runs, wickets)
- [ ] Wait 2-3 seconds
- [ ] Check if overlay on live stream updates

### **5. YouTube Integration**
- [ ] Stream appears on YouTube
- [ ] Score overlay is visible on YouTube stream
- [ ] Overlay updates on YouTube when scores change

---

## 🔍 Debugging Tips

### **Check Console Logs:**
Look for these messages:
- `✅ RTMP Stream started successfully`
- `📊 Scorecard updated - refreshing overlay`
- `✅ Pushing overlay to stream: X bytes`
- `✅ Overlay updated successfully on stream`

### **If Overlay Doesn't Update:**
1. Check if scorecard is being fetched:
   - Look for `Error fetching initial scorecard` in logs
2. Check if overlay is being pushed:
   - Look for `Pushing overlay to stream` messages
3. Verify scorecard data:
   - Check Supabase `matches` table for `scorecard` field
   - Ensure it's being updated when you score

### **If Camera Doesn't Work:**
- **Emulator:** Camera won't work - use physical device
- **Physical Device:** Check camera permissions in app settings

---

## 🚀 Quick Test Commands

```bash
# 1. Check available devices
flutter devices

# 2. Run on emulator (UI testing only)
flutter run -d emulator-5554

# 3. Run on physical device (full testing)
flutter run -d <device-id>

# 4. Hot reload after changes
# Press 'r' in terminal or use IDE hot reload

# 5. Check logs
flutter logs
```

---

## 📝 Testing Checklist

- [ ] App runs without errors
- [ ] Can navigate to Go Live screen
- [ ] Camera initializes (on physical device)
- [ ] "GO LIVE" button works
- [ ] Stop button appears when streaming
- [ ] Live indicator appears and animates
- [ ] Score overlay appears
- [ ] Score overlay updates when scores change
- [ ] Stop button stops the stream
- [ ] Stream appears on YouTube (if configured)
- [ ] Overlay is visible on YouTube stream

---

## 🆘 Troubleshooting

**Problem: Camera not initializing**
- **Solution:** Use physical device, not emulator

**Problem: Overlay not updating**
- **Solution:** Check console logs for errors
- Verify scorecard is being saved to database
- Check if `_updateStreamOverlay()` is being called

**Problem: Stop button not visible**
- **Solution:** Check if `_isStreaming` is true
- Verify the Positioned widget is in the Stack

**Problem: Stream not appearing on YouTube**
- **Solution:** Check YouTube API credentials
- Verify Mux service is configured
- Check network connectivity

---

## 💡 Pro Tips

1. **Test with two devices:**
   - Device 1: Stream the match
   - Device 2: Watch the stream and update scores
   - This tests the full flow

2. **Use YouTube Studio:**
   - Monitor your YouTube channel for live streams
   - Verify overlay appears correctly

3. **Check Supabase:**
   - Monitor `match_live_streams` table
   - Check `matches.scorecard` for updates

4. **Enable verbose logging:**
   - Add more `print()` statements if needed
   - Use Flutter DevTools for better debugging

