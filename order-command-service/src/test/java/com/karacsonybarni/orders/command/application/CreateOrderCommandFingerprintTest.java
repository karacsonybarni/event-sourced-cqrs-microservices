package com.karacsonybarni.orders.command.application;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.List;

import org.junit.jupiter.api.Test;

class CreateOrderCommandFingerprintTest {

    private final CreateOrderCommandFingerprint fingerprint = new CreateOrderCommandFingerprint();

    @Test
    void treatsEquivalentDecimalRepresentationsAsTheSameLogicalCommand() {
        var first = command("customer-42", "keyboard", "49.90");
        var replay = command("customer-42", "keyboard", "49.900");

        assertThat(fingerprint.calculate(first)).isEqualTo(fingerprint.calculate(replay));
    }

    @Test
    void changesWhenCommandPayloadChanges() {
        var first = command("first-customer", "keyboard", "49.90");
        var different = command("different-customer", "monitor", "299.90");

        assertThat(fingerprint.calculate(first)).isNotEqualTo(fingerprint.calculate(different));
    }

    private static CreateOrderCommand command(String customerId, String productId, String unitPrice) {
        var item = new CreateOrderCommand.Item(productId, 1, new BigDecimal(unitPrice));
        return new CreateOrderCommand(customerId, List.of(item));
    }
}
