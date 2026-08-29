FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S -g 10001 spring && adduser -S -u 10001 -G spring spring
USER 10001:10001
COPY --chmod=0444 order-query-service/target/order-query-service-*.jar app.jar
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"
EXPOSE 8082
ENTRYPOINT ["java", "-jar", "/app.jar"]
