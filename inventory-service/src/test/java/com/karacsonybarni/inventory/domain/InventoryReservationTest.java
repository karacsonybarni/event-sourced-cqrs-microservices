package com.karacsonybarni.inventory.domain;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.Test;

class InventoryReservationTest {

    @Test
    void releaseIsIdempotentAndPreservesReservedItemsForCompensation() {
        Instant reservedAt = Instant.parse("2026-01-10T10:15:30Z");
        var reservation = InventoryReservation.reserve(
                UUID.randomUUID(),
                List.of(new ReservedItem("keyboard", 2)),
                reservedAt);

        boolean firstReleaseChangedState = reservation.release(reservedAt.plusSeconds(30));
        boolean repeatedReleaseChangedState = reservation.release(reservedAt.plusSeconds(60));

        assertThat(firstReleaseChangedState).isTrue();
        assertThat(repeatedReleaseChangedState).isFalse();
        assertThat(reservation.getStatus()).isEqualTo(ReservationStatus.RELEASED);
        assertThat(reservation.getItems())
                .singleElement()
                .satisfies(item -> {
                    assertThat(item.productId()).isEqualTo("keyboard");
                    assertThat(item.quantity()).isEqualTo(2);
                });
    }
}
