import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.util.Base64;

public class TestDecrypt {

    public static String aesDecrypt(String encode, String key) throws Exception {
        byte[] encrypted = safeUrlBase64Decode(encode);
        byte[] enCodeFormat = key.getBytes(StandardCharsets.UTF_8);
        SecretKeySpec skeySpec = new SecretKeySpec(enCodeFormat, "AES");
        Cipher cipher = Cipher.getInstance("AES/ECB/PKCS5Padding");
        cipher.init(Cipher.DECRYPT_MODE, skeySpec);
        byte[] original = cipher.doFinal(encrypted);
        return new String(original, StandardCharsets.UTF_8);
    }

    public static byte[] safeUrlBase64Decode(String data) {
        String base64 = data.replace("-", "+").replace("_", "/");
        int padding = 4 - (base64.length() % 4);
        if (padding != 4) {
            base64 += "=".repeat(padding);
        }
        return Base64.getDecoder().decode(base64);
    }

    public static void main(String[] args) throws Exception {
        String encode = "Zx5BNyqN_UP8lZJ7X_mWtQ";
        String key = "087508df8f524bfcb8b2902cf3ea1440";
        
        System.out.println("密文: " + encode);
        System.out.println("密钥: " + key);
        System.out.println("密钥长度: " + key.length() + " 字节");
        
        try {
            String result = aesDecrypt(encode, key);
            System.out.println("\n解密结果: " + result);
        } catch (Exception e) {
            System.out.println("\n解密失败: " + e.getMessage());
            e.printStackTrace();
        }
    }
}
