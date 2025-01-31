package com.example.main

import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.provider.Settings.Secure
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import javax.security.auth.x500.X500Principal
import java.util.concurrent.Executor

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.example.main/platform_channel"
    private var signedData: ByteArray? = null // To store signed data
    private var imageData: ByteArray? = null // To store image data
    private var aliasPrefix: String = ""

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNativeMessage" -> {
                        result.success("Hello from Android!")
                    }
                    "checkAndGenerateKeyPair" -> {
                        aliasPrefix = call.argument<String>("aliasPrefix") ?: ""
                        val (deviceId, message) = checkAndGenerateKeyPair()
                        result.success("Device ID: $deviceId, $message")
                    }
                    "requestBiometricAuth" -> {
                        val imageBase64 = call.argument<String>("imageBase64") ?: ""
                        imageData = Base64.decode(imageBase64, Base64.DEFAULT)
                        createBiometricPromptForSignature { authResult ->
                            result.success(authResult)
                        }
                    }
                    "verifySignature" -> {
                        val signedKeyInput = call.argument<String>("signedKeyInput") ?: ""
                        val imageBase64 = call.argument<String>("imageBase64") ?: ""
                        imageData = Base64.decode(imageBase64, Base64.DEFAULT)
                        verifySignature(signedKeyInput) { verificationResult ->
                            result.success(verificationResult)
                        }
                    }
                    "copySignedKeyToClipboard" -> {
                        copySignedKeyToClipboard()
                        result.success("Signed key copied to clipboard.")
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    private fun retrieveDeviceId(): String {
        return Secure.getString(contentResolver, Secure.ANDROID_ID)
    }

    private fun checkAndGenerateKeyPair(): Pair<String, String> {
        val deviceId = retrieveDeviceId()
        val alias = "$aliasPrefix$deviceId"

        return try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

            if (keyStore.containsAlias(alias)) {
                val publicKey = getPublicKey(alias) // Retrieve public key
                deviceId to "Key Pair already exists with : $alias, Public Key: $publicKey"
            } else {
                generateKeyPair(alias)
                val publicKey = getPublicKey(alias) // Retrieve newly generated public key
                deviceId to "Key Pair generated successfully with alias: $alias, Public Key: $publicKey"
            }
        } catch (e: Exception) {
            deviceId to "Error checking key pair: ${e.message}"
        }
    }

    private fun generateKeyPair(alias: String) {
        val keyPairGenerator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
        keyPairGenerator.initialize(
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
            )
                .setCertificateSubject(X500Principal("CN=$alias"))
                .setCertificateSerialNumber(BigInteger.ONE)
                .setCertificateNotBefore(java.util.Date())
                .setCertificateNotAfter(java.util.Date(System.currentTimeMillis() + 365 * 24 * 60 * 60 * 1000)) // 1 year validity
                .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA512)
                .setUserAuthenticationRequired(true)
                .build()
        )
        keyPairGenerator.generateKeyPair()
    }

    private fun getPublicKey(alias: String): String {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val publicKeyEntry = keyStore.getCertificate(alias).publicKey
        return Base64.encodeToString(publicKeyEntry.encoded, Base64.NO_WRAP)
    }

    private fun createBiometricPromptForSignature(onResult: (String) -> Unit) {
        val executor: Executor = ContextCompat.getMainExecutor(this)
        val biometricPrompt = BiometricPrompt(this, executor, object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                val errorMsg = "Authentication error: $errString (Code: $errorCode)"
                Log.e("BiometricAuth", errorMsg)
                onResult(errorMsg)
            }

            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                val cryptoObject = result.cryptoObject
                performKeyAccess(cryptoObject) { accessResult ->
                    onResult(accessResult)
                }
            }

            override fun onAuthenticationFailed() {
                onResult("Authentication failed")
            }
        })

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Biometric Authentication")
            .setSubtitle("Authenticate using your biometric credential")
            .setNegativeButtonText("Cancel")
            .build()

        val deviceId = retrieveDeviceId()
        val alias = "$aliasPrefix$deviceId"
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val key = keyStore.getKey(alias, null) as? java.security.PrivateKey
        val signature = Signature.getInstance("SHA256withECDSA").apply {
            initSign(key)
        }

        biometricPrompt.authenticate(promptInfo, BiometricPrompt.CryptoObject(signature))
    }

    private fun performKeyAccess(cryptoObject: BiometricPrompt.CryptoObject?, onResult: (String) -> Unit) {
        if (cryptoObject == null) {
            val errorMsg = "Error: CryptoObject is null, unable to sign data."
            Log.e("KeyAccess", errorMsg)
            onResult(errorMsg)
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            val accessMessage = try {
                if (imageData == null) {
                    throw IllegalStateException("Image data is null")
                }

                val signature = cryptoObject.signature ?: throw IllegalStateException("No signature available")
                signature.update(imageData)
                signedData = signature.sign() // Save the signed data

                // Convert signed data to a hex string for display
                val signedDataHex = signedData!!.joinToString("") { "%02x".format(it) }
                "$signedDataHex"
            } catch (e: Exception) {
                val errorMsg = "Error accessing key: ${e.message}"
                Log.e("KeyAccess", errorMsg, e)
                errorMsg
            }
            withContext(Dispatchers.Main) {
                onResult(accessMessage)
            }
        }
    }

    private fun verifySignature(signedKeyInput: String, onResult: (String) -> Unit) {
        val deviceId = retrieveDeviceId()
        val alias = "$aliasPrefix$deviceId"
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

        if (!keyStore.containsAlias(alias)) {
            onResult("Error: Key does not exist.")
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            val verificationResult = try {
                val publicKeyEntry = keyStore.getEntry(alias, null) as KeyStore.PrivateKeyEntry
                val publicKey = publicKeyEntry.certificate.publicKey
                val signature = Signature.getInstance("SHA256withECDSA").apply {
                    initVerify(publicKey)
                }

                // Convert the hex string input to a byte array
                val signedDataFromInput = signedKeyInput.chunked(2)
                    .mapNotNull { it.toIntOrNull(16)?.toByte() }
                    .toByteArray()

                // Verify the signature using the image data used for signing
                if (imageData == null) {
                    throw IllegalStateException("Image data is null")
                }
                signature.update(imageData)
                val isVerified = signature.verify(signedDataFromInput)

                "Signature verification result: $isVerified"
            } catch (e: Exception) {
                val errorMsg = "Error verifying signature: ${e.message}"
                Log.e("SignatureVerification", errorMsg, e)
                errorMsg
            }
            withContext(Dispatchers.Main) {
                onResult(verificationResult)
            }
        }
    }

    private fun copySignedKeyToClipboard() {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val signedDataHex = signedData?.joinToString("") { "%02x".format(it) }

        if (signedDataHex != null) {
            val clip = android.content.ClipData.newPlainText("Signed Key", signedDataHex)
            clipboard.setPrimaryClip(clip)
        } else {
            Log.e("Clipboard", "No signed key available to copy.")
        }
    }
}
