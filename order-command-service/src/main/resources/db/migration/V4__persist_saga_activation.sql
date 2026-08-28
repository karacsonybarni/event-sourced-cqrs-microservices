CREATE TABLE saga_configuration (
    configuration_key VARCHAR(100) PRIMARY KEY,
    activation_at TIMESTAMP WITH TIME ZONE NOT NULL
);

INSERT INTO saga_configuration (configuration_key, activation_at)
VALUES ('inventory-saga-activation', '${sagaActivationAt}'::timestamptz);
