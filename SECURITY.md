# Security

Clipboard history can contain sensitive data. encore excludes common password managers and pasteboard content marked confidential or temporary by default, but cannot reliably detect every secret. Browser extensions may omit these markers. Exclude the host application when needed.

Library files and JSON backups are stored unencrypted. Library permissions restrict ordinary access to the current macOS account; they do not protect against another process running as that user or an administrator. File references can outlive, or lose access to, their source files.

The initial release is ad-hoc signed, is not notarized, and has not undergone an independent security audit. Do not rely on encore as a password or secrets manager.

To report a vulnerability, use the repository's private vulnerability reporting feature if enabled. Avoid public reports containing sensitive clipboard data. If private reporting is unavailable, open an issue asking for a private contact route without including the vulnerability details or any personal content.
