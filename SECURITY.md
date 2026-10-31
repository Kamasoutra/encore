# Security

Clipboard history can contain sensitive data. encore excludes common password managers and pasteboard content marked confidential or temporary by default, but cannot reliably detect every secret. Browser extensions may omit these markers. Exclude the host application when needed.

Since 0.7, the library and its contents are encrypted on disk with ChaCha20-Poly1305, under a 256-bit key kept in the login keychain; this can be turned off in Settings → Data. Exported JSON backups are not encrypted. Encryption at rest protects copies of the files; it does not protect against software that already runs as the user while encore is open, since encore itself reads the clipboard. Pairing keys for other Macs are kept in a separate file readable only by the user. File references can outlive, or lose access to, their source files.

The initial release is ad-hoc signed, is not notarized, and has not undergone an independent security audit. Do not rely on encore as a password or secrets manager.

To report a vulnerability, use the repository's private vulnerability reporting feature if enabled. Avoid public reports containing sensitive clipboard data. If private reporting is unavailable, open an issue asking for a private contact route without including the vulnerability details or any personal content.
