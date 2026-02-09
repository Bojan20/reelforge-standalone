//! Undo/Redo system using command pattern

use std::collections::VecDeque;

/// Trait for undoable commands
pub trait Command: Send + Sync {
    /// Execute the command
    fn execute(&mut self);

    /// Undo the command
    fn undo(&mut self);

    /// Get command name for display
    fn name(&self) -> &str;

    /// Whether this command can be merged with a previous command
    fn can_merge(&self, _other: &dyn Command) -> bool {
        false
    }

    /// Merge with previous command (called if can_merge returns true)
    fn merge(&mut self, _other: Box<dyn Command>) {}
}

/// Undo/Redo manager
pub struct UndoManager {
    undo_stack: VecDeque<Box<dyn Command>>,
    redo_stack: Vec<Box<dyn Command>>,
    max_history: usize,
    group_depth: usize,
    group_commands: Vec<Box<dyn Command>>,
}

impl UndoManager {
    pub fn new(max_history: usize) -> Self {
        Self {
            undo_stack: VecDeque::with_capacity(max_history),
            redo_stack: Vec::new(),
            max_history,
            group_depth: 0,
            group_commands: Vec::new(),
        }
    }

    /// Execute a command and add it to the undo stack
    pub fn execute(&mut self, mut command: Box<dyn Command>) {
        command.execute();

        if self.group_depth > 0 {
            self.group_commands.push(command);
        } else {
            self.push_command(command);
        }

        // Clear redo stack on new command
        self.redo_stack.clear();
    }

    fn push_command(&mut self, command: Box<dyn Command>) {
        // Try to merge with previous command
        if let Some(last) = self.undo_stack.back_mut()
            && last.can_merge(command.as_ref())
        {
            last.merge(command);
            return;
        }

        // Enforce max history
        while self.undo_stack.len() >= self.max_history {
            self.undo_stack.pop_front();
        }

        self.undo_stack.push_back(command);
    }

    /// Undo the last command
    pub fn undo(&mut self) -> bool {
        if let Some(mut command) = self.undo_stack.pop_back() {
            command.undo();
            self.redo_stack.push(command);
            true
        } else {
            false
        }
    }

    /// Redo the last undone command
    pub fn redo(&mut self) -> bool {
        if let Some(mut command) = self.redo_stack.pop() {
            command.execute();
            self.undo_stack.push_back(command);
            true
        } else {
            false
        }
    }

    /// Start a command group (grouped commands are undone/redone together)
    pub fn begin_group(&mut self) {
        self.group_depth += 1;
    }

    /// End a command group
    pub fn end_group(&mut self, name: &str) {
        if self.group_depth > 0 {
            self.group_depth -= 1;

            if self.group_depth == 0 && !self.group_commands.is_empty() {
                let commands = std::mem::take(&mut self.group_commands);
                let group = GroupCommand::new(name.to_string(), commands);
                self.push_command(Box::new(group));
            }
        }
    }

    /// Check if undo is available
    pub fn can_undo(&self) -> bool {
        !self.undo_stack.is_empty()
    }

    /// Check if redo is available
    pub fn can_redo(&self) -> bool {
        !self.redo_stack.is_empty()
    }

    /// Get the name of the next undo command
    pub fn undo_name(&self) -> Option<&str> {
        self.undo_stack.back().map(|c| c.name())
    }

    /// Get the name of the next redo command
    pub fn redo_name(&self) -> Option<&str> {
        self.redo_stack.last().map(|c| c.name())
    }

    /// Clear all history
    pub fn clear(&mut self) {
        self.undo_stack.clear();
        self.redo_stack.clear();
        self.group_commands.clear();
        self.group_depth = 0;
    }

    /// Get number of undo steps
    pub fn undo_count(&self) -> usize {
        self.undo_stack.len()
    }

    /// Get number of redo steps
    pub fn redo_count(&self) -> usize {
        self.redo_stack.len()
    }
}

/// Group of commands that are undone/redone together
struct GroupCommand {
    name: String,
    commands: Vec<Box<dyn Command>>,
}

impl GroupCommand {
    fn new(name: String, commands: Vec<Box<dyn Command>>) -> Self {
        Self { name, commands }
    }
}

impl Command for GroupCommand {
    fn execute(&mut self) {
        for cmd in &mut self.commands {
            cmd.execute();
        }
    }

    fn undo(&mut self) {
        for cmd in self.commands.iter_mut().rev() {
            cmd.undo();
        }
    }

    fn name(&self) -> &str {
        &self.name
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    struct SetValueCommand {
        value: Arc<Mutex<i32>>,
        old_value: i32,
        new_value: i32,
    }

    impl Command for SetValueCommand {
        fn execute(&mut self) {
            let mut v = self.value.lock().unwrap();
            self.old_value = *v;
            *v = self.new_value;
        }

        fn undo(&mut self) {
            *self.value.lock().unwrap() = self.old_value;
        }

        fn name(&self) -> &str {
            "Set Value"
        }
    }

    #[test]
    fn test_undo_redo() {
        let mut manager = UndoManager::new(100);
        let value = Arc::new(Mutex::new(0));

        manager.execute(Box::new(SetValueCommand {
            value: Arc::clone(&value),
            old_value: 0,
            new_value: 1,
        }));
        assert_eq!(*value.lock().unwrap(), 1);

        manager.execute(Box::new(SetValueCommand {
            value: Arc::clone(&value),
            old_value: 0,
            new_value: 2,
        }));
        assert_eq!(*value.lock().unwrap(), 2);

        assert!(manager.undo());
        assert_eq!(*value.lock().unwrap(), 1);

        assert!(manager.redo());
        assert_eq!(*value.lock().unwrap(), 2);
    }

    #[test]
    fn test_group() {
        let mut manager = UndoManager::new(100);
        let value = Arc::new(Mutex::new(0));

        manager.begin_group();
        manager.execute(Box::new(SetValueCommand {
            value: Arc::clone(&value),
            old_value: 0,
            new_value: 1,
        }));
        manager.execute(Box::new(SetValueCommand {
            value: Arc::clone(&value),
            old_value: 0,
            new_value: 2,
        }));
        manager.end_group("Multiple Sets");

        assert_eq!(*value.lock().unwrap(), 2);
        assert_eq!(manager.undo_count(), 1);

        assert!(manager.undo());
        assert_eq!(*value.lock().unwrap(), 0);
    }
}
