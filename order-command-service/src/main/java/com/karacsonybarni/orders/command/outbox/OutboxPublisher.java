package com.karacsonybarni.orders.command.outbox;

import java.time.Clock;
import java.time.Instant;
import java.util.concurrent.TimeUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
class OutboxPublisher {

    private static final Logger LOGGER = LoggerFactory.getLogger(OutboxPublisher.class);
    private static final int BATCH_SIZE = 50;

    private final OutboxEventRepository repository;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final Clock clock;
    private final String topic;

    OutboxPublisher(
            OutboxEventRepository repository,
            KafkaTemplate<String, String> kafkaTemplate,
            Clock clock,
            @Value("${orders.events.topic}") String topic) {
        this.repository = repository;
        this.kafkaTemplate = kafkaTemplate;
        this.clock = clock;
        this.topic = topic;
    }

    @Scheduled(fixedDelayString = "${orders.outbox.publish-interval:500}")
    @Transactional
    public void publishPendingEvents() throws Exception {
        var unpublishedEvents = repository.findUnpublished(PageRequest.of(0, BATCH_SIZE));
        for (OutboxEvent event : unpublishedEvents) {
            kafkaTemplate.send(topic, event.getAggregateId().toString(), event.getPayload())
                    .get(10, TimeUnit.SECONDS);
            Instant publishedAt = clock.instant();
            event.markPublished(publishedAt);
            LOGGER.info("Published outbox event {} for order {}", event.getEventId(), event.getAggregateId());
        }
    }
}
