package com.karacsonybarni.orders.command.application;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

import org.springframework.stereotype.Component;

@Component
class CreateOrderCommandFingerprint {

    String calculate(CreateOrderCommand command) {
        var canonicalCommand = new StringBuilder();
        append(canonicalCommand, command.customerId());
        canonicalCommand.append(command.items().size()).append(':');
        for (CreateOrderCommand.Item item : command.items()) {
            append(canonicalCommand, item.productId());
            canonicalCommand.append(item.quantity()).append(':');
            String normalizedUnitPrice = item.unitPrice().stripTrailingZeros().toPlainString();
            append(canonicalCommand, normalizedUnitPrice);
        }

        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] fingerprint = digest.digest(canonicalCommand.toString().getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(fingerprint);
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private static void append(StringBuilder target, String value) {
        target.append(value.length()).append(':').append(value);
    }
}
