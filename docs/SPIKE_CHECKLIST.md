# Duo test session script

This is for whoever is holding the iPhone Duo. It takes about 20 minutes. The app does the measuring; you just follow the prompts and send the log at the end.

## Before you start

- [ ] Install **TestFlight** from the App Store. Accept the invite email from the developer, then install **DuoProbe**.
- [ ] Charge the phone above 50%.
- [ ] Find a room with a textured wall or a bookshelf, and a clear 2 m to walk in.
- [ ] When the app asks for camera access, allow it.

## Hold it like this ("Posture A")

1. Open the phone about halfway, to roughly a right angle.
2. Hold it like a book standing upright, hinge vertical.
3. Turn it so the **small outer screen faces you**.
4. The half you're looking at stays still. The other half sticks out forward, away from you.
5. Closing = swing the forward half shut onto the half you're holding, like a sideways clap. **Normal speed, never slam it.**

## Run the tests

Open DuoProbe and tap each test in order. Each one shows its own instructions on screen. Some pictures look sideways or mirrored: that's on purpose. If a test says "not available", that's a result too: just move on.

| Test | What you do |
|---|---|
| P1 Device info | Tap Run |
| P2 Cameras | Hold Posture A. Tap Find cameras, then tap each camera in turn and say what it shows. For the one that shows the room in front of you, tap "Shows the room in front of me" |
| P3 Inner camera | Hold Posture A, pointing at the wall. Tap Start camera. Rate the picture (sharp / OK / blurry), say which yellow-labelled edge is nearest the hinge, and how much of the picture the other half of the phone blocks |
| P4 Outer screen | Open the phone fully and tap Start camera. Say how the app looks on the big screen. Then go to Posture A and say what the small outer screen shows |
| P4b Outer screen picture | Only in the Mac-built version (P1 says "SDK 27.1 native"). Otherwise skip it. Open fully, tap Start camera, look at the small outer screen, then fold to Posture A and answer the three questions |
| P5 Hinge | Tap Start in Posture A. Close it slowly once, then at normal speed 5 times, reopening to Posture A each time. Tap Stop and analyse |
| P6 Darkness | Tap Start in Posture A. 5 normal-speed closes, reopening each time. Tap Stop and analyse |
| P7 AR tracking | Hold Posture A and tap Start. For 20 seconds, walk slowly towards the wall and back, twice |
| P8 Two cameras | Tap Start and wait about 10 seconds |
| P9 Clips | Tap Start camera, then record 3 clips: walk up to the wall, close slowly, close at normal speed |
| P10 Close signals | Tap Start in Posture A. Close at normal speed 3 times; each time, look at the small outer screen while it's shut, then reopen. Tap Stop and answer the two questions |
| P11 Motion sensors | At a table. Phase 1: hold the half facing you still and gently swing the far half. Phase 2: the other way round. 5 seconds each, gentle movements only |
| P12 Posture B | Open the phone wide (about 130°), big inner screen facing you, back of the phone towards the room. Tap Start, turn slowly left and right for 10 seconds, then say how the app fills the big screen |

## Finish

- [ ] Tap **Share log** and send it (and the clips) to the developer. WhatsApp, Messages or AirDrop are all fine. Don't use "Save Video" in that menu.
- [ ] Note anything odd that the log won't show: the app froze, something felt weird to hold, the screen went black.

Phases 5 and 6 add a short script below for each new build.

## Build: CatchTheFly Duo 1

The first game build for the Duo, made on the Mac-less CI route (Xcode 27.1). About 25 minutes. Install **Catch the Fly** from TestFlight. Allow camera and motion access when asked. Headphones help with the buzzing.

Safety first: clear 2 m around you, look up before you move, and fold **calmly**. A gentle fold scores exactly as well as a hard one. If you see "Gently does it", you folded harder than you need to.

### Setting up (phone fully open)

- [ ] Open the phone flat. The big screen shows a copy of the game on the left and "Hold it like a book" on the right. Make sure **Posture A** is ticked.
- [ ] Turn the phone round and look at the small outer screen. **Is the camera picture there, with "Start round" at the bottom?** (yes / no / blank)
- [ ] Fold to Posture A (the L, like at the top of this page). Does the small screen keep showing the picture? Is it **upright** and **not mirrored**? (Wave your right hand: it should move on the right of the picture.)

If the small screen stays blank with the phone open, skip to "Posture B" below and say so in your notes.

### Test 1: a full round by folding (about 5 min)

- [ ] In Posture A, tap **Show zone** on the small screen. A red dashed box marks the hit zone.
- [ ] Tap **Start round**. Stand about 1 m from a bookshelf or a poster. Listen for the buzz, find the fly, creep up until it takes off and hovers.
- [ ] Keep it inside the red box, then fold the far half shut, calmly.
- [ ] You should feel a thud and hear a splat **straight away**, while the phone is shut. Note if it came late, or not at all.
- [ ] With the phone shut, does the small screen show "Splat!"? Open it back to the L: is "Splat!" still on the small screen?
- [ ] Catch all 3 flies. At the end: "Round complete" with your time.

### Test 2: no false smashes (2 min)

- [ ] Start a round and just hunt the fly for **2 minutes** without folding. Turn, walk slowly, tilt the phone, open it a bit wider and back. **Don't fold it shut.**
- [ ] Count any "Splat!" or "Missed!" that appeared without you folding. It should be 0.

### Test 3: 10 deliberate smashes (about 10 min)

- [ ] Each time: wait until the fly hovers inside the red box, then fold shut at a normal, calm speed. Reopen to the L.
- [ ] Tally hits ("Splat!") and misses ("Missed!") out of 10. The target is at least 7 hits.
- [ ] Note whether the misses had something in common (the fly near the hinge, near the far edge, far away).

### Things only you can tell us

- [ ] When you turn left, does the fly move right across the picture, the way a real object would? If it slides the wrong way, open the phone flat, tap **Flip the turning direction**, and test again. Note which setting worked.
- [ ] Which side of the small screen's picture is nearest the hinge: left or right? Is the red box on that side?
- [ ] Did the picture on the small screen ever freeze, go black or turn sideways while the phone was open?

### Posture B (the fallback, about 3 min)

- [ ] Open the phone flat, tap **Posture B**. Now open it wide (about 130°), big screen facing you, back of the phone towards the room.
- [ ] Play one round: find the fly, keep it in the middle (tap **Debug** to see the red box), and close the book on it, calmly.
- [ ] Note: did hits register? Did the camera switch to the back camera? To return, tap **Posture B** at the top left and pick Posture A.

### Finish

- [ ] On the big screen, tap **Share log** and send it to the developer, with your tallies and notes.
