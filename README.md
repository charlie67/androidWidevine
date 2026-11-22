Tools to extract Widevine DRM keys from an Android emulator. Following these instructions generates a device folder which contains the device client_id and private_key for decrypting Widevine DRM. 


1. Run start-emulator
2. Run `keydive -kw -a player`
3. Follow these steps within the app:
    1. Provision Widevine (if the device isn't provisioned).
    2. Refresh to intercept the keybox or private key.
    3. Test DRM Playback to extract the challenge.


See also: https://github.com/hyugogirubato/KeyDive/blob/main/README.md