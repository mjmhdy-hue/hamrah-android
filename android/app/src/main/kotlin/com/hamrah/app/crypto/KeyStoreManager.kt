package com.hamrah.app.crypto

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import android.util.Log
import java.io.File
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class KeyUnavailableException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * Android Keystore AES-256-GCM key (non-exportable, StrongBox when available) wrapping two
 * independent random 32-byte DB passphrases stored as ciphertext in app-private storage.
 * Nothing here ever writes a plaintext passphrase to disk.
 */
class KeyStoreManager(private val context: Context) {

    companion object {
        private const val TAG = "HamrahKeys"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val ALIAS = "hamrah_master_v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_BITS = 128
        private const val FILE_VERSION: Byte = 1
        private const val MAIN = "main"
        private const val NATIVE = "native"
    }

    private val dir: File = File(context.filesDir, "keys").apply { mkdirs() }

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun loadOrCreateKey(): SecretKey {
        val ks = keyStore()
        val existing = ks.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        val spec = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .build()
        return try {
            generator.init(spec)
            generator.generateKey()
        } catch (e: StrongBoxUnavailableException) {
            Log.w(TAG, "StrongBox unavailable, falling back to TEE", e)
            val fallback = KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
            generator.init(fallback)
            generator.generateKey()
        }
    }

    private fun passphraseFile(name: String) = File(dir, "$name.key")

    @Synchronized
    fun passphrase(name: String): String {
        require(name == MAIN || name == NATIVE)
        val file = passphraseFile(name)
        return try {
            val key = loadOrCreateKey()
            if (!file.exists()) {
                val random = ByteArray(32).also { SecureRandom().nextBytes(it) }
                val plain = Base64.encodeToString(random, Base64.NO_WRAP).toByteArray(Charsets.UTF_8)
                val cipher = Cipher.getInstance(TRANSFORMATION)
                cipher.init(Cipher.ENCRYPT_MODE, key)
                val iv = cipher.iv
                val encrypted = cipher.doFinal(plain)
                plain.fill(0)
                file.outputStream().use { out ->
                    out.write(byteArrayOf(FILE_VERSION))
                    out.write(byteArrayOf(iv.size.toByte()))
                    out.write(iv)
                    out.write(encrypted)
                }
                Base64.encodeToString(random, Base64.NO_WRAP)
            } else {
                val bytes = file.readBytes()
                if (bytes.isEmpty() || bytes[0] != FILE_VERSION) throw KeyUnavailableException("bad_key_file")
                val ivLength = bytes[1].toInt() and 0xFF
                if (bytes.size < 2 + ivLength + 1) throw KeyUnavailableException("truncated_key_file")
                val iv = bytes.copyOfRange(2, 2 + ivLength)
                val payload = bytes.copyOfRange(2 + ivLength, bytes.size)
                val cipher = Cipher.getInstance(TRANSFORMATION)
                cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
                String(cipher.doFinal(payload), Charsets.UTF_8)
            }
        } catch (e: KeyUnavailableException) {
            throw e
        } catch (e: Exception) {
            // Never delete or regenerate an existing key file: the databases would become unreadable.
            throw KeyUnavailableException("keystore_failure", e)
        }
    }

    fun mainPassphrase(): String = passphrase(MAIN)

    fun nativePassphrase(): String = passphrase(NATIVE)

    fun isKeyPresent(): Boolean = try {
        keyStore().containsAlias(ALIAS) && passphraseFile(MAIN).exists() && passphraseFile(NATIVE).exists()
    } catch (e: Exception) {
        false
    }

    fun state(): String = try {
        if (isKeyPresent()) "ok" else "missing"
    } catch (e: Exception) {
        "unavailable"
    }
}
