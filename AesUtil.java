import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.util.Base64;

public class AesUtil {

    /**
     * AES 加密 (ECB/PKCS5Padding)
     */
    public static String aesEncrypt(String content, String key) throws Exception {
        byte[] contentBytes = content.getBytes(StandardCharsets.UTF_8);
        byte[] keyBytes = key.getBytes(StandardCharsets.UTF_8);
        
        SecretKeySpec skeySpec = new SecretKeySpec(keyBytes, "AES");
        Cipher cipher = Cipher.getInstance("AES/ECB/PKCS5Padding");
        cipher.init(Cipher.ENCRYPT_MODE, skeySpec);
        
        byte[] encrypted = cipher.doFinal(contentBytes);
        return safeUrlBase64Encode(encrypted);
    }

    /**
     * AES 解密 (ECB/PKCS5Padding) —— 你提供的方法
     */
    public static String aesDecrypt(String encode, String key) throws Exception {
        byte[] encrypted = safeUrlBase64Decode(encode);
        byte[] enCodeFormat = key.getBytes(StandardCharsets.UTF_8);
        SecretKeySpec skeySpec = new SecretKeySpec(enCodeFormat, "AES");
        Cipher cipher = Cipher.getInstance("AES/ECB/PKCS5Padding");
        cipher.init(Cipher.DECRYPT_MODE, skeySpec);
        byte[] original = cipher.doFinal(encrypted);
        return new String(original, StandardCharsets.UTF_8);
    }

    /**
     * URL-safe Base64 编码
     */
    public static String safeUrlBase64Encode(byte[] data) {
        String base64 = Base64.getEncoder().encodeToString(data);
        return base64.replace("+", "-").replace("/", "_");
    }

    /**
     * URL-safe Base64 解码
     */
    public static byte[] safeUrlBase64Decode(String data) {
        String base64 = data.replace("-", "+").replace("_", "/");
        // 补齐 padding
        int padding = 4 - (base64.length() % 4);
        if (padding != 4) {
            base64 += "=".repeat(padding);
        }
        return Base64.getDecoder().decode(base64);
    }

    // 测试
    public static void main(String[] args) throws Exception {
        String key = "1234567890123456";  // 16字节密钥
        String text = "Hello, World! 测试";

        String encrypted = aesEncrypt(text, key);
        System.out.println("加密结果: " + encrypted);

        String decrypted = aesDecrypt(encrypted, key);
        System.out.println("解密结果: " + decrypted);
        System.out.println("验证: " + text.equals(decrypted));
    }
}
