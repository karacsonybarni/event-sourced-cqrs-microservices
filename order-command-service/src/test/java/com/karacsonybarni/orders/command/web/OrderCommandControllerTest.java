package com.karacsonybarni.orders.command.web;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.karacsonybarni.orders.command.application.OrderCommandService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(OrderCommandController.class)
class OrderCommandControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private OrderCommandService service;

    @Test
    void invalidNestedBodyReturnsProblemDetailWithoutCallingService() throws Exception {
        mockMvc.perform(post("/api/orders")
                        .header("Idempotency-Key", "valid-key")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"customerId":"","items":[]}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.status").value(400))
                .andExpect(jsonPath("$.detail").value(containsString("customerId")))
                .andExpect(jsonPath("$.detail").value(containsString("must not be blank")));

        verifyNoInteractions(service);
    }

    @Test
    void blankIdempotencyKeyReturnsProblemDetailWithoutCallingService() throws Exception {
        mockMvc.perform(post("/api/orders")
                        .header("Idempotency-Key", " ")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"customerId":"customer-42","items":[
                                  {"productId":"keyboard","quantity":1,"unitPrice":49.90}
                                ]}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.status").value(400))
                .andExpect(jsonPath("$.detail").value(containsString("Idempotency-Key")))
                .andExpect(jsonPath("$.detail").value(containsString("must not be blank")));

        verifyNoInteractions(service);
    }

    @Test
    void missingIdempotencyKeyReturnsProblemDetailWithoutCallingService() throws Exception {
        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"customerId":"customer-42","items":[
                                  {"productId":"keyboard","quantity":1,"unitPrice":49.90}
                                ]}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.status").value(400))
                .andExpect(jsonPath("$.detail").value(containsString("Idempotency-Key")))
                .andExpect(jsonPath("$.detail").value(containsString("required")));

        verifyNoInteractions(service);
    }
}
