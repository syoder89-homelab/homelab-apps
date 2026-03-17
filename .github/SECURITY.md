# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this repository, please report it responsibly:

1. **Do not** open a public issue.
2. Email [syoder89@gmail.com](mailto:syoder89@gmail.com) with details of the vulnerability.
3. Include steps to reproduce, if possible.

## Security Practices

- All commits must be GPG-signed.
- Secrets are managed via sealed secrets or external secrets — never committed in plaintext.
- Dependabot is enabled for dependency vulnerability scanning.
- GitHub secret scanning and push protection are enabled.
