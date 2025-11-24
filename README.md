# Sinclo (MVP)

1. Open `Sinclo.xcodeproj` in Xcode.
2. Select the Sinclo target, enable Signing & Capabilities, add iCloud Documents, add your container identifier.
3. Ensure the entitlements file is attached to the target.
4. Build & Run.
5. On first run, use Add Folder to choose your Downloads folder (security bookmark will be required for persistent access).
```

---

## Next steps I can do right now
- Provide an Xcode-ready `Package.swift` and minimal project files to import into Xcode. (I can generate that next.)
- Replace `DispatchSource` with `FSEvents` for recursive folder tree watching.
- Add SecurityScopedBookmark support to persist permission to watch arbitrary user folders across launches.
- Add conflict resolution UI and sync status table in the menubar UI.


---

End of scaffold. Save this as the initial codebase and open in Xcode.

---
