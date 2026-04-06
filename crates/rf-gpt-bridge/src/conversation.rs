// file: crates/rf-gpt-bridge/src/conversation.rs
//! Conversation memory — maintains context across GPT exchanges.
//!
//! This is NOT just a message buffer. It's intelligent context management:
//! - Rolling window with importance-based retention
//! - Automatic summarization trigger when window is full
//! - Separate channels for different intent types

use crate::protocol::{GptIntent, GptMessage};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;

/// A conversation exchange (request + response pair).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Exchange {
    /// The query sent to GPT.
    pub query: GptMessage,
    /// The response received.
    pub response: GptMessage,
    /// Intent of this exchange.
    pub intent: GptIntent,
    /// When this exchange happened.
    pub timestamp: DateTime<Utc>,
    /// Importance score (0.0 = trivial, 1.0 = critical). Higher = retained longer.
    pub importance: f32,
    /// Tokens consumed by this exchange.
    pub tokens: u32,
}

/// Conversation memory with intelligent retention.
#[derive(Debug)]
pub struct ConversationMemory {
    /// System prompt (always first in context).
    system_prompt: GptMessage,
    /// Rolling window of exchanges.
    exchanges: VecDeque<Exchange>,
    /// Maximum number of exchanges to keep.
    max_exchanges: usize,
    /// Total tokens used in this session.
    total_tokens_used: u32,
    /// Summary of evicted exchanges (compressed context).
    context_summary: Option<String>,
    /// Total exchanges ever (including evicted).
    total_exchanges: u64,
    /// Pending user message (sent to browser, waiting for response).
    pending_user_message: Option<GptMessage>,
}

impl ConversationMemory {
    /// Create a new conversation memory.
    pub fn new(system_prompt: impl Into<String>, max_exchanges: usize) -> Self {
        Self {
            system_prompt: GptMessage::system(system_prompt),
            exchanges: VecDeque::with_capacity(max_exchanges),
            max_exchanges,
            total_tokens_used: 0,
            context_summary: None,
            total_exchanges: 0,
            pending_user_message: None,
        }
    }

    /// Record a completed exchange.
    pub fn record(&mut self, query: String, response: String, intent: GptIntent, tokens: u32, importance: f32) {
        let exchange = Exchange {
            query: GptMessage::user(query),
            response: GptMessage::assistant(response),
            intent,
            timestamp: Utc::now(),
            importance: importance.clamp(0.0, 1.0),
            tokens,
        };

        self.total_tokens_used += tokens;
        self.total_exchanges += 1;

        // If at capacity, evict lowest-importance exchange
        if self.exchanges.len() >= self.max_exchanges {
            self.evict_least_important();
        }

        self.exchanges.push_back(exchange);
    }

    /// Build the messages array to send to GPT API.
    /// Includes system prompt, context summary, and recent exchanges.
    pub fn build_messages(&self, new_query: &str) -> Vec<GptMessage> {
        let mut messages = Vec::with_capacity(self.exchanges.len() * 2 + 3);

        // 1. System prompt (always first)
        messages.push(self.system_prompt.clone());

        // 2. Context summary (if we have evicted exchanges)
        if let Some(ref summary) = self.context_summary {
            messages.push(GptMessage::system(format!(
                "[Kontekst prethodnih razgovora]: {}",
                summary
            )));
        }

        // 3. Recent exchanges (chronological)
        for exchange in &self.exchanges {
            messages.push(exchange.query.clone());
            messages.push(exchange.response.clone());
        }

        // 4. New query
        messages.push(GptMessage::user(new_query));

        messages
    }

    /// Total tokens used in this session.
    pub fn total_tokens_used(&self) -> u32 {
        self.total_tokens_used
    }

    /// Number of exchanges in memory.
    pub fn exchange_count(&self) -> usize {
        self.exchanges.len()
    }

    /// Total exchanges ever (including evicted).
    pub fn total_exchanges(&self) -> u64 {
        self.total_exchanges
    }

    /// Update the system prompt.
    pub fn set_system_prompt(&mut self, prompt: impl Into<String>) {
        self.system_prompt = GptMessage::system(prompt);
    }

    /// Set context summary (from summarization of evicted exchanges).
    pub fn set_context_summary(&mut self, summary: impl Into<String>) {
        self.context_summary = Some(summary.into());
    }

    /// Add a user message (for browser bridge — query sent, response pending).
    pub fn add_user_message(&mut self, content: &str) {
        // Store as a partial exchange — will be completed when assistant responds.
        // For now, just track it so build_messages includes it.
        self.pending_user_message = Some(GptMessage::user(content));
    }

    /// Add an assistant message (for browser bridge — completes pending exchange).
    pub fn add_assistant_message(&mut self, content: &str) {
        if let Some(user_msg) = self.pending_user_message.take() {
            self.record(
                user_msg.content,
                content.to_string(),
                GptIntent::Insight, // default intent
                0, // no token count from browser
                0.5, // default importance
            );
        }
    }

    /// Clear all conversation history (keeps system prompt).
    pub fn clear(&mut self) {
        self.exchanges.clear();
        self.context_summary = None;
    }

    /// Get recent exchanges for a specific intent.
    pub fn exchanges_by_intent(&self, intent: GptIntent) -> Vec<&Exchange> {
        self.exchanges.iter().filter(|e| e.intent == intent).collect()
    }

    /// Evict the least important exchange and update context summary.
    fn evict_least_important(&mut self) {
        if self.exchanges.is_empty() {
            return;
        }

        // Find index of least important exchange
        let min_idx = self
            .exchanges
            .iter()
            .enumerate()
            .min_by(|(_, a), (_, b)| a.importance.partial_cmp(&b.importance).unwrap_or(std::cmp::Ordering::Equal))
            .map(|(i, _)| i)
            .unwrap_or(0);

        if let Some(evicted) = self.exchanges.remove(min_idx) {
            // Append evicted exchange to context summary (compressed)
            let summary_line = format!(
                "[{}] {}: {}",
                evicted.intent_tag(),
                evicted.query.content.chars().take(100).collect::<String>(),
                evicted.response.content.chars().take(200).collect::<String>()
            );

            match &mut self.context_summary {
                Some(existing) => {
                    existing.push('\n');
                    existing.push_str(&summary_line);
                    // Keep summary under 2000 chars
                    if existing.len() > 2000 {
                        // Trim from the front (oldest summaries)
                        if let Some(pos) = existing[existing.len() - 1800..].find('\n') {
                            let trim_pos = existing.len() - 1800 + pos + 1;
                            *existing = existing[trim_pos..].to_string();
                        }
                    }
                }
                None => {
                    self.context_summary = Some(summary_line);
                }
            }
        }
    }
}

impl Exchange {
    fn intent_tag(&self) -> &'static str {
        match self.intent {
            GptIntent::Analysis => "ANALIZA",
            GptIntent::Architecture => "ARHITEKTURA",
            GptIntent::Debugging => "DEBUG",
            GptIntent::CodeReview => "REVIEW",
            GptIntent::Insight => "INSIGHT",
            GptIntent::UserQuery => "KORISNIK",
            GptIntent::Creative => "KREATIVA",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::GptRole;

    #[test]
    fn conversation_memory_basic() {
        let mut mem = ConversationMemory::new("Test system prompt", 3);
        assert_eq!(mem.exchange_count(), 0);

        mem.record("Pitanje 1".into(), "Odgovor 1".into(), GptIntent::Insight, 100, 0.5);
        mem.record("Pitanje 2".into(), "Odgovor 2".into(), GptIntent::Analysis, 200, 0.8);

        assert_eq!(mem.exchange_count(), 2);
        assert_eq!(mem.total_tokens_used(), 300);
    }

    #[test]
    fn conversation_memory_eviction() {
        let mut mem = ConversationMemory::new("System", 2);

        mem.record("Low importance".into(), "R1".into(), GptIntent::Insight, 50, 0.1);
        mem.record("High importance".into(), "R2".into(), GptIntent::Debugging, 50, 0.9);
        // This should evict the low-importance one
        mem.record("New one".into(), "R3".into(), GptIntent::Analysis, 50, 0.5);

        assert_eq!(mem.exchange_count(), 2);
        // The low-importance exchange should be evicted
        assert!(mem.context_summary.is_some());
    }

    #[test]
    fn build_messages_structure() {
        let mut mem = ConversationMemory::new("Ti si GPT", 10);
        mem.record("Kako si?".into(), "Dobro sam.".into(), GptIntent::Insight, 20, 0.5);

        let messages = mem.build_messages("Novo pitanje");

        // system + exchange(user+assistant) + new query = 4
        assert_eq!(messages.len(), 4);
        assert_eq!(messages[0].role, GptRole::System);
        assert_eq!(messages[1].role, GptRole::User);
        assert_eq!(messages[2].role, GptRole::Assistant);
        assert_eq!(messages[3].role, GptRole::User);
        assert_eq!(messages[3].content, "Novo pitanje");
    }

    #[test]
    fn intent_filtering() {
        let mut mem = ConversationMemory::new("System", 10);
        mem.record("Q1".into(), "A1".into(), GptIntent::Debugging, 10, 0.5);
        mem.record("Q2".into(), "A2".into(), GptIntent::Analysis, 10, 0.5);
        mem.record("Q3".into(), "A3".into(), GptIntent::Debugging, 10, 0.5);

        let debug_exchanges = mem.exchanges_by_intent(GptIntent::Debugging);
        assert_eq!(debug_exchanges.len(), 2);
    }
}
