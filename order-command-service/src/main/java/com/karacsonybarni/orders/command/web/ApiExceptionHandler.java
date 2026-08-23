package com.karacsonybarni.orders.command.web;

import java.util.stream.Stream;

import com.karacsonybarni.orders.command.application.IdempotencyKeyConflictException;
import com.karacsonybarni.orders.command.domain.OrderNotFoundException;
import org.springframework.context.MessageSourceResolvable;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.validation.FieldError;
import org.springframework.validation.method.ParameterErrors;
import org.springframework.validation.method.ParameterValidationResult;
import org.springframework.web.bind.MissingRequestHeaderException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.HandlerMethodValidationException;

@RestControllerAdvice
class ApiExceptionHandler {

    @ExceptionHandler(IdempotencyKeyConflictException.class)
    ProblemDetail idempotencyConflict(IdempotencyKeyConflictException exception) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, exception.getMessage());
    }

    @ExceptionHandler(OrderNotFoundException.class)
    ProblemDetail orderNotFound(OrderNotFoundException exception) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, exception.getMessage());
    }

    @ExceptionHandler(MissingRequestHeaderException.class)
    ProblemDetail missingRequestHeader(MissingRequestHeaderException exception) {
        String detail = exception.getHeaderName() + ": is required";
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, detail);
    }

    @ExceptionHandler(HandlerMethodValidationException.class)
    ProblemDetail methodValidationFailed(HandlerMethodValidationException exception) {
        String detail = exception.getParameterValidationResults().stream()
                .flatMap(ApiExceptionHandler::validationMessages)
                .sorted()
                .findFirst()
                .orElse("Request validation failed");
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, detail);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ProblemDetail validationFailed(MethodArgumentNotValidException exception) {
        String detail = exception.getBindingResult().getFieldErrors().stream()
                .map(error -> error.getField() + ": " + error.getDefaultMessage())
                .findFirst()
                .orElse("Request validation failed");
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, detail);
    }

    private static Stream<String> validationMessages(ParameterValidationResult result) {
        if (result instanceof ParameterErrors errors) {
            Stream<String> fieldMessages = errors.getFieldErrors().stream()
                    .map(ApiExceptionHandler::fieldValidationMessage);
            String parameterName = parameterName(result);
            Stream<String> globalMessages = errors.getGlobalErrors().stream()
                    .map(error -> parameterName + ": " + defaultMessage(error));
            return Stream.concat(fieldMessages, globalMessages);
        }

        String parameterName = parameterName(result);
        return result.getResolvableErrors().stream()
                .map(error -> parameterName + ": " + defaultMessage(error));
    }

    private static String fieldValidationMessage(FieldError error) {
        return error.getField() + ": " + defaultMessage(error);
    }

    private static String parameterName(ParameterValidationResult result) {
        RequestHeader requestHeader = result.getMethodParameter().getParameterAnnotation(RequestHeader.class);
        if (requestHeader != null && !requestHeader.name().isBlank()) {
            return requestHeader.name();
        }
        String parameterName = result.getMethodParameter().getParameterName();
        return parameterName != null ? parameterName : "request";
    }

    private static String defaultMessage(MessageSourceResolvable error) {
        String defaultMessage = error.getDefaultMessage();
        return defaultMessage != null ? defaultMessage : "is invalid";
    }
}
