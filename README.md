<p align="center">
  <img src="https://github.com/user-attachments/assets/02d7432b-58e4-4a08-800b-b868d4dcc1a9" width="30%" alt="IMG_3108" />
  <img src="https://github.com/user-attachments/assets/747b49f9-ef37-4ee9-8177-0d03e21fa07a" width="30%" alt="IMG_3106" />
  <img src="https://github.com/user-attachments/assets/d718f93c-5c9f-4057-a833-f40c9abb73eb" width="30%" alt="IMG_3107" />
</p>

# ScreenDistancePill

Replaces the full-screen Screen Distance warning ("iPhone is Too Close",
iOS 17) with a small pill under the Dynamic Island / Notch. The pill blocks nothing and
goes away by itself once the face is far enough away (or no longer seen).

## Settings
Tested on iOS 17.1.1 roothide (iPhone 15 Pro):
- 👁️ Warning Sensitivity page: Distance and Remind After.
- 🎨 Appearance page:
  - Animation: Fade In/Out time (0.2–1.2 s, default 0.6), Check Mark time,
    Edge Glow (off by default: an orange glow along the screen edges if the
    phone is still too close 5–25 s after the pill appears), and Orange Glow
    (with its strength, 50–150 %) / Bouncing Icon so the pill is harder to
    miss.
  - Feedback: Haptic Feedback when the pill appears.
- 🚫 Exclude page: Excluded Apps and Excluded Time.

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

</details>

<details>
<summary>What the tweak does</summary>


- `eyereliefd` (`Daemon.x`): `-[ERDaemonManager interveneWithType:withCompletion:]`
  no longer opens the remote alert. It posts `…/PillShow`, then repeats
  `-[EREyeReliefEngine takeDistanceSampleWithCompletion:]` every 0.3 s. As soon
  as `ERDistanceEvent.distanceCategory` is not 0 it posts `…/PillHide` and calls
  the completion with outcome 2, so the daemon carries on as if Continue had
  been tapped at a safe distance. Categories come from
  `+[ERAttentionAwarenessClient _categoryForDistance:withTooCloseDistanceThreshold:withFaceState:]`:
  0 too close, 1 at or beyond the threshold, 2 no face. A failed sample or
  180 s without a safe one post `…/PillCancel` instead.
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
  lock and after 200 s, and posts `…/PillDismissed` so the daemon stops
  sampling.
- Before showing the pill SpringBoard checks Excluded Apps (the bundle id of
  `-[SpringBoard _accessibilityFrontMostApplication]`) and Excluded Time.
  If one applies it posts `…/PillSuppressed`; eyereliefd ends the reminder
  with outcome 2 as if the phone had been moved away. Unlike Apple's own list,
  sampling keeps going in excluded apps; they just never get a reminder.
- Enabled, Debug, Distance and Remind After reach eyereliefd as notify states
  (`…/Enabled`, `…/Debug`, `…/Threshold` in mm, `…/Sensitivity` in samples)
  that SpringBoard publishes at launch and whenever the settings change,
  because eyereliefd's sandbox may not be able to read the plist.

</details>

## License

© 2026 Qn (Đạt Nguyễn). Licensed under [GNU GPLv3](LICENSE).


