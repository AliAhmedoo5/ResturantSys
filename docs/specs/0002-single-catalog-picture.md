# Single catalog picture

Confirmed on 2026-10-24 through the grill-with-docs interview.

- A Menu Item and a Deal each have one optional picture.
- Click the picture area to open the native single-file browser, or drop one
  local image onto it. Multiple-file drops are rejected without changing it.
- Keep the control compact: a 64px preview within an approximately 90px row,
  using the existing dark surfaces, yellow focus/accent and spacing tokens.
- Accept JPEG, PNG and WebP up to 5 MiB; verify content and decoding before
  replacing the preview. Invalid or unreadable files leave the previous picture.
- Change and Remove stage edits. Save commits them; Cancel or dismiss discards
  them. Failed saves retain the existing picture and allow retry.
- Include the control directly in Menu Item creation and editing. There is no
  Deal definition editor in the current application; expose the same compact
  picture editor for existing Deals in the Manager catalog workspace.
- Replacing/removing retires all active legacy gallery pictures for that owner
  in the same database transaction. Old files remain available for recovery.
  Opening/canceling an editor does not change legacy data.
- Menu Item fields and its picture commit together, including first creation;
  a failed save must not leave an extra item behind.

Validation runs exclusively in GitHub Actions, including Windows plugin build
verification. No local Flutter builds or tests.
