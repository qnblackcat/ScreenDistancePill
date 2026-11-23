<p align="center">
  <img src="https://github.com/user-attachments/assets/a3220ff4-3c95-43b1-87b8-b035d7a2e2e6" width="30%" alt="1" />
  <img src="https://github.com/user-attachments/assets/dec358d3-5784-4fd2-ab45-7687fd7e9ea4" width="30%" alt="2" />
  <img src="https://github.com/user-attachments/assets/6e1b9afc-6d90-4231-9b44-f813f094df53" width="30%" alt="3" />
</p>

# ScreenDistancePill

Shows a small pill instead of the full-screen "iPhone is Too Close" warning. On iPhones that have Dynamic Island, you can choose to shows 
the eye icon in the Dynamic Island instead of the pill

Starting from version 2.0.0, the tweak also includes the Screen Distance feature that was previously only available in iOS 17 but has been backported to iOS 16.

<details>
<summary>How the stock warning works</summary>

- `eyereliefd` (`EyeRelief.framework/Resources/eyereliefd`) samples the face
  distance through AttentionAwareness every 80 s (`NSBackgroundActivityScheduler`,
  5 s tolerance). Each too-close sample adds 1 to
  `-[EREyeReliefEngine tooCloseCount]`, a normal one takes 1 off; at 4 the
  engine asks for an intervention, so about 5 minutes of continuous close use.
  It then calls `-[ERDaemonManager interveneWithType:withCompletion:]`, which
  opens a SpringBoard remote alert: service `com.apple.EyeReliefUI`, view
  controller `EyeReliefUI.ViewController`.
- `-[ERDaemonManager nonPermissibleOnscreenContent]` is Apple's own list of
  apps during which sampling stops (Camera, FaceTime, Settings, Messages,
  Phone, Photo Booth, InCallService).
- `/Applications/EyeReliefUI.app` draws that shield in SwiftUI (videos
  `TooClose.mov` / `Success.mov`). It never closes by itself: Continue sends a
  `BSActionResponse` back to `eyereliefd` (outcome 2 at a safe distance), and
  only then does the daemon schedule its next sample.
- iOS 16 has no Screen Distance at all: no `EyeRelief.framework`, no
  `eyereliefd`, no `EyeReliefUI.app`. What it does have is Face ID's
  Attention Aware feature, which runs inside `backboardd`:
  `AWPearlAttentionSampler` (AttentionAwareness) owns the `BKDevicePearl` and
  samples the face through BiometricKit (`BKFaceDetectOperation`). Its events
  carry only the head angles (pitch, yaw, roll) and orientation. The distance
  is one layer lower: iOS 16's `BKFaceDetectStateInfo` has `distance` (mm) and
  `faceDetected`, which AttentionAwareness ignores. iOS 17 passes the same
  distance up (`AWFaceDetectAttentionEvent.distance` plus a `faceState`)
  for `ERAttentionAwarenessClient` to use. iOS 15.0's `BKFaceDetectStateInfo`
  has no distance and its raw face data has a different layout, so there is
  nothing to read there.

</details>

<details>
<summary>What the tweak does</summary>

The part that measures differs per iOS, the rest is shared. On iOS 17+ the tweak
hooks `eyereliefd` (`Daemon.x`); on iOS 16 it runs its own sampler in
`backboardd` (`Daemon16.xm`). Both talk to SpringBoard (`Pill.x`) through the
same `…/PillShow`, `…/PillHide`, `…/PillCancel`, `…/PillDismissed` and
`…/PillSuppressed` notifications, and use the same settings.

**iOS 17+ (`Daemon.x`, in `eyereliefd`)**

- `eyereliefd` (`Daemon.x`): `-[ERDaemonManager interveneWithType:withCompletion:]`
  no longer opens the remote alert. It posts `…/PillShow`, then repeats
  `-[EREyeReliefEngine takeDistanceSampleWithCompletion:]` every 0.3 s. As soon
  as `ERDistanceEvent.distanceCategory` is not 0 it posts `…/PillHide` and calls
  the completion with outcome 2, so the daemon carries on as if Continue had
  been tapped at a safe distance. Categories come from
  `+[ERAttentionAwarenessClient _categoryForDistance:withTooCloseDistanceThreshold:withFaceState:]`:
  0 too close, 1 at or beyond the threshold, 2 no face. A failed sample or
  180 s without a safe one post `…/PillCancel` instead.
- Threshold and Sensitivity apply only while Custom Sensitivity is on; off,
  both stay iOS's own.
- Threshold: `tooCloseDistanceThreshold` on both `EREyeReliefEngine` and
  `ERAttentionAwarenessClient` returns the Distance setting (stock 300 mm), so
  the reminder and the pill's "far enough" use the same value.
- Sensitivity: while `-[EREyeReliefEngine _processDistanceEvent:]` runs,
  increases of `tooCloseCount` are scaled by 4 / N, so the fixed limit of 4 is
  reached after N too-close samples (2 / 4 / 6 / 8 ≈ 3 / 5 / 8 / 11 minutes).
  Decreases and every other write (outcome, inactivity, restore from
  defaults) are left alone.
- `…/PillShow` carries flags as its notify state: ignore the rules (Show Now)
  and test (marked as such in the log).

**iOS 16 (`Daemon16.xm`, in `backboardd`)**

- It does what `eyereliefd` does on iOS 17. The first sample is taken 20 s after
  `backboardd` starts, then one every 80 s. A sample runs a
  `BKFaceDetectOperation` on the `BKDevicePearl` of `AWPearlAttentionSampler`
  (about half a second, no camera indicator, no camera permission), and reads
  `faceDetected` and `distance` (mm) from the last `BKFaceDetectStateInfo`.
- Each sample gets the same category iOS 17 uses: no face is 2, a face closer
  than the threshold is 0 (too close), a face at or beyond it is 1. Too close
  adds 4 / N to the count (N is Sensitivity, 4 stock, so 1 each), far enough
  takes 1 off, no face takes 0.25 off, and the count stays between 0 and 4; at
  4 the reminder is due and the count restarts from 0. A sample without a face
  is not trusted for its distance: BiometricKit can report one anyway.
  The count is not saved, so it starts again whenever `backboardd` restarts.
- A reminder posts `…/PillShow` and keeps sampling (about every 0.55 s, one
  sample takes that long) until the face is far enough or gone (`…/PillHide`)
  or 180 s have passed (`…/PillCancel`), like on iOS 17.
- No sample is taken while the screen is off or locked
  (`com.apple.springboard.hasBlankedScreen`, `…lockstate`), while the pill is
  up, or while the front app is one of Apple's own exclusions (Camera,
  FaceTime, Settings, Messages, Phone, Photo Booth, InCallService, the list in
  `eyereliefd` on iOS 17). `backboardd` does not know the front app, so it asks
  SpringBoard (`…/FrontAppQuery`, answered with the `…/FrontApp` state and
  `…/FrontAppReply`); with no answer in 1 s it samples anyway.
- The test buttons in Settings reach `backboardd` through the same
  `…/Trigger` and `…/TriggerDelayed` notifications.
- Not covered on iOS 16 yet: the Dynamic Island option. The pill has no bounce
  (SF Symbol effects are iOS 17+) and uses a built-in title, as EyeReliefUI does
  not exist.
- Restarting the daemon (Settings, or after install) restarts `backboardd`,
  which respring the device.

**Both**

- SpringBoard (`Pill.x`): a window above the status bar that ignores touches,
  with a capsule under the Dynamic Island showing EyeReliefUI's own localized
  `TOO_CLOSE_TITLE_STRING_IPHONE`. The capsule is a system thick material
  (follows light / dark mode) with a hairline border and a soft shadow, and an
  orange eye icon in a tinted circle. While it is up, the pill beats every
  3.2 s off one timer: Bouncing Icon bounces the icon (SF Symbol bounce
  effect) and Orange Glow swaps the hairline border for an orange glow and tint
  over the material that flare up at the same moment (the tint is stronger in dark mode, where the
  material is near black). Edge Glow, if on, fades in four orange gradients
  along the screen edges (under the pill) once the pill has been up for the
  set time, beating with it. On `…/PillHide` the icon turns into a
  green check mark (the glow and tint, if on, turn steady green), which stays for a while before the pill fades out (the edge glow fades out
  right away);
  `…/PillCancel` fades it out directly. SpringBoard also takes the pill down on
  lock and after 200 s, and only then posts `…/PillDismissed` so the daemon
  stops sampling.
- Before showing the pill SpringBoard checks Excluded Apps (the bundle id of
  `-[SpringBoard _accessibilityFrontMostApplication]`) and Excluded Time.
  If one applies it posts `…/PillSuppressed`; the daemon ends the reminder
  (eyereliefd with outcome 2) as if the phone had been moved away. Unlike
  Apple's own list, sampling keeps going in apps you exclude; they just never
  get a reminder.
- Enabled, Debug, Distance and Remind After reach `eyereliefd` (iOS 17+) or
  `backboardd` (iOS 16) as notify states
  (`…/Enabled`, `…/Debug`, `…/Threshold` in mm, `…/Sensitivity` in samples,
  both 0 while Custom Sensitivity is off) that SpringBoard publishes at launch and whenever the settings change,
  because the daemons' sandbox may not be able to read the plist.

</details>


## Building

<details>
<summary>Build instructions</summary>

Build the package with roothide's fork of Theos. 

```sh
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

</details>

## License

ScreenDistancePill is licensed under the GNU General Public License, version 3 only. See [LICENSE](LICENSE).

© 2026 Qn (Đạt Nguyễn)


