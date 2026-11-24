//! Source protocol registry. The registry distinguishes implemented providers
//! from protocols reserved for future integration; there are no fake providers.
//! This is the iOS reference frontend inventory, NOT a cross-platform
//! availability or runtime compatibility probe. Rust owns the policy; the
//! frontend owns authentication, transports and platform permissions.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceProtocol {
    Local,
    Https,
    Smb,
    Sftp,
    Ftp,
    WebDav,
    Nfs,
    Upnp,
}

#[derive(Debug, Clone, Copy)]
pub struct ProviderInfo {
    pub protocol: SourceProtocol,
    pub implemented: bool,
    pub browsing: bool,
    pub streaming: bool,
}

pub const PROVIDERS: [ProviderInfo; 8] = [
    ProviderInfo {
        protocol: SourceProtocol::Local,
        implemented: true,
        browsing: true,
        streaming: true,
    },
    ProviderInfo {
        protocol: SourceProtocol::Https,
        implemented: true,
        browsing: false,
        streaming: true,
    },
    ProviderInfo {
        protocol: SourceProtocol::Smb,
        implemented: true,
        browsing: true,
        streaming: true,
    },
    ProviderInfo {
        protocol: SourceProtocol::Sftp,
        implemented: true,
        browsing: true,
        streaming: true,
    },
    ProviderInfo {
        protocol: SourceProtocol::Ftp,
        implemented: false,
        browsing: false,
        streaming: false,
    },
    ProviderInfo {
        protocol: SourceProtocol::WebDav,
        implemented: true,
        browsing: true,
        streaming: true,
    },
    ProviderInfo {
        protocol: SourceProtocol::Nfs,
        implemented: false,
        browsing: false,
        streaming: false,
    },
    ProviderInfo {
        protocol: SourceProtocol::Upnp,
        implemented: false,
        browsing: false,
        streaming: false,
    },
];

pub fn provider(protocol: SourceProtocol) -> &'static ProviderInfo {
    PROVIDERS
        .iter()
        .find(|info| info.protocol == protocol)
        .expect("every source protocol must be registered")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn protocols_have_explicit_status() {
        assert!(provider(SourceProtocol::Local).browsing);
        assert!(provider(SourceProtocol::Https).streaming);
        for protocol in [SourceProtocol::Sftp, SourceProtocol::WebDav, SourceProtocol::Smb] {
            assert!(provider(protocol).implemented);
            assert!(provider(protocol).browsing);
        }
        for protocol in [SourceProtocol::Ftp, SourceProtocol::Nfs, SourceProtocol::Upnp] {
            assert!(!provider(protocol).implemented);
        }
    }
}
