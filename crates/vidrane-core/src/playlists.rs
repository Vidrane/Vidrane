//! Platform-neutral playlist editing rules.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Playlist {
    pub name: String,
    entries: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaylistError {
    InvalidPosition,
}

impl Playlist {
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            entries: Vec::new(),
        }
    }

    pub fn entries(&self) -> &[String] {
        &self.entries
    }

    /// Adds each URI/file identifier at most once.
    pub fn add(&mut self, media_id: impl Into<String>) -> bool {
        let media_id = media_id.into();
        if media_id.is_empty() || self.entries.contains(&media_id) {
            return false;
        }
        self.entries.push(media_id);
        true
    }

    pub fn remove(&mut self, media_id: &str) -> bool {
        if let Some(index) = self.entries.iter().position(|entry| entry == media_id) {
            self.entries.remove(index);
            true
        } else {
            false
        }
    }

    pub fn move_entry(&mut self, from: usize, to: usize) -> Result<(), PlaylistError> {
        if from >= self.entries.len() || to >= self.entries.len() {
            return Err(PlaylistError::InvalidPosition);
        }
        let entry = self.entries.remove(from);
        self.entries.insert(to, entry);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn playlist_deduplicates_entries() {
        let mut list = Playlist::new("Favorites");
        assert!(list.add("movie.mkv"));
        assert!(!list.add("movie.mkv"));
        assert_eq!(list.entries().len(), 1);
        assert!(list.remove("movie.mkv"));
        assert!(!list.remove("movie.mkv"));
    }

    #[test]
    fn reordering_is_bounded() {
        let mut list = Playlist::new("History");
        list.add("a");
        list.add("b");
        list.add("c");
        list.move_entry(0, 2).unwrap();
        assert_eq!(list.entries(), &["b", "c", "a"]);
        assert_eq!(list.move_entry(0, 3), Err(PlaylistError::InvalidPosition));
    }
}
