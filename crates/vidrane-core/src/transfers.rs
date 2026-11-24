//! Download/transfer state machine used by upcoming background-aware queues.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransferState {
    Queued,
    Running,
    Paused,
    Completed,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransferError {
    InvalidTransition,
    InvalidByteCount,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Transfer {
    pub id: String,
    pub state: TransferState,
    pub received_bytes: u64,
    pub total_bytes: Option<u64>,
}

impl Transfer {
    pub fn new(id: impl Into<String>, total_bytes: Option<u64>) -> Self {
        Self {
            id: id.into(),
            state: TransferState::Queued,
            received_bytes: 0,
            total_bytes,
        }
    }

    pub fn start(&mut self) -> Result<(), TransferError> {
        match self.state {
            TransferState::Queued | TransferState::Paused => {
                self.state = TransferState::Running;
                Ok(())
            }
            _ => Err(TransferError::InvalidTransition),
        }
    }

    pub fn progress(&mut self, bytes: u64) -> Result<(), TransferError> {
        if self.state != TransferState::Running {
            return Err(TransferError::InvalidTransition);
        }
        let received = self
            .received_bytes
            .checked_add(bytes)
            .ok_or(TransferError::InvalidByteCount)?;
        if self.total_bytes.is_some_and(|total| received > total) {
            return Err(TransferError::InvalidByteCount);
        }
        self.received_bytes = received;
        Ok(())
    }

    pub fn pause(&mut self) -> Result<(), TransferError> {
        if self.state != TransferState::Running {
            return Err(TransferError::InvalidTransition);
        }
        self.state = TransferState::Paused;
        Ok(())
    }

    pub fn complete(&mut self) -> Result<(), TransferError> {
        if self.state != TransferState::Running {
            return Err(TransferError::InvalidTransition);
        }
        if self.total_bytes.is_some_and(|total| self.received_bytes != total) {
            return Err(TransferError::InvalidByteCount);
        }
        self.state = TransferState::Completed;
        Ok(())
    }

    pub fn fail(&mut self) -> Result<(), TransferError> {
        if self.state != TransferState::Running {
            return Err(TransferError::InvalidTransition);
        }
        self.state = TransferState::Failed;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transfer_transitions() {
        let mut transfer = Transfer::new("download", Some(100));
        assert_eq!(transfer.progress(1), Err(TransferError::InvalidTransition));
        transfer.start().unwrap();
        transfer.progress(30).unwrap();
        transfer.pause().unwrap();
        assert_eq!(transfer.received_bytes, 30);
        transfer.start().unwrap();
        transfer.progress(70).unwrap();
        transfer.complete().unwrap();
        assert_eq!(transfer.state, TransferState::Completed);
    }

    #[test]
    fn completion_rejects_incomplete_known_length() {
        let mut transfer = Transfer::new("download", Some(100));
        transfer.start().unwrap();
        transfer.progress(99).unwrap();
        assert_eq!(transfer.complete(), Err(TransferError::InvalidByteCount));
        assert_eq!(transfer.state, TransferState::Running);
        transfer.progress(1).unwrap();
        transfer.complete().unwrap();
    }

    #[test]
    fn byte_overflow_is_rejected() {
        let mut transfer = Transfer::new("download", Some(2));
        transfer.start().unwrap();
        assert_eq!(transfer.progress(3), Err(TransferError::InvalidByteCount));
        assert_eq!(transfer.received_bytes, 0);
    }
}
