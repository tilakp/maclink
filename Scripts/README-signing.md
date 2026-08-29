# Making the Accessibility permission stick

## The problem

macOS TCC identifies an app by its code signing *designated requirement*, not
by its path or bundle ID. An ad-hoc signed app has no certificate to anchor to,
so its requirement degrades to a literal hash of the binary:

    $ codesign -d -r- /Applications/maclink.app
    designated => cdhash H"87978f20e3719d78d234b5b444e659942c7beff8"

Every rebuild changes that hash. The Accessibility grant stops matching and
capture silently stops working, while System Settings still shows the checkbox
as enabled. Removing and re-adding the app rewrites the entry with the new
hash, and the next build breaks it again.

## The fix: a self-signed code signing certificate

This is free and takes about a minute. No Apple Developer account needed.
TCC does not require the certificate to be trusted by Apple. It only requires
the anchor to be stable across rebuilds.

1. Open **Keychain Access**.
2. Menu: **Keychain Access > Certificate Assistant > Create a Certificate…**
3. Fill in:
   - **Name:** `maclink-dev` (the exact name `build-app.sh` looks for)
   - **Identity Type:** Self Signed Root
   - **Certificate Type:** **Code Signing**
   - Leave "Let me override defaults" unchecked.
4. Click Create, then Done.

Verify the identity is there. Note the *lack* of `-v`:

    security find-identity -p codesigning

You should see `maclink-dev` under "Matching identities", marked
`CSSMERR_TP_NOT_TRUSTED`, and "0 valid identities found" below it.

That is expected and fine. A self-signed root is untrusted by definition, so
it is filtered out of the `-v` (valid only) list. It still signs, the signature
still verifies (`codesign --verify --strict` passes), and TCC still honors it,
because TCC matches the designated requirement rather than checking Apple
trust. There is no need to mark the certificate as trusted, which would mean
an admin password for no benefit.

5. Rebuild and install:

       Scripts/install.sh

   It now prints `==> signing identity: maclink-dev` instead of falling back
   to ad-hoc.

6. **One last time**, remove maclink from System Settings > Privacy & Security
   > Accessibility and re-add `/Applications/maclink.app`. This writes a TCC
   entry keyed to the certificate. Do the same under Automation if capture
   still fails.

From then on the requirement looks like this, and stays identical across
rebuilds:

    designated => identifier "com.tilak.maclink" and certificate leaf H"..."

## Using a Developer ID instead

If you get a paid Apple Developer account later, sign with that identity:

    MACLINK_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" Scripts/install.sh

Changing identity changes the designated requirement, so the permission needs
re-granting once more on that switch.
