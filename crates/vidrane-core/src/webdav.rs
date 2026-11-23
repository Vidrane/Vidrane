//! Parse DAV:multistatus XML independent of any platform-specific HTTP client.
//!
//! XML is untrusted. The parser does not fetch external entities (roxmltree
//! disallows DTD by default). All network href validation stays in the
//! transport adapter, which must restrict paths and origins.
use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct DavEntry {
    pub href: String,
    pub display_name: String,
    pub is_directory: bool,
    pub size: Option<u64>,
}

fn dav_tag(node: roxmltree::Node<'_, '_>, name: &str) -> bool {
    node.is_element()
        && node.tag_name().name() == name
        && node.tag_name().namespace() == Some("DAV:")
}

fn dav_child<'a, 'input>(
    parent: roxmltree::Node<'a, 'input>,
    name: &str,
) -> Option<roxmltree::Node<'a, 'input>> {
    parent.children().find(|node| dav_tag(*node, name))
}

/// Extract the response-level href and successful DAV properties.
/// We intentionally ignore properties from non-2xx propstat blocks.
pub fn parse_multistatus(input: &str) -> Result<Vec<DavEntry>, &'static str> {
    let doc = roxmltree::Document::parse(input).map_err(|_| "invalid XML")?;
    let root = doc.root_element();
    if !dav_tag(root, "multistatus") {
        return Err("not DAV:multistatus");
    }
    let mut result = Vec::new();
    for response in root.children().filter(|node| dav_tag(*node, "response")) {
        let Some(href) = dav_child(response, "href").and_then(|node| node.text()) else {
            continue;
        };
        let href = href.trim();
        if href.is_empty() {
            continue;
        }
        let mut entry = DavEntry {
            href: href.to_string(),
            display_name: String::new(),
            is_directory: false,
            size: None,
        };
        for stat in response.children().filter(|node| dav_tag(*node, "propstat")) {
            let ok = dav_child(stat, "status")
                .and_then(|node| node.text())
                .map(|status| status.split_whitespace().any(|part| {
                    part.len() == 3
                        && part.starts_with('2')
                        && part.bytes().all(|byte| byte.is_ascii_digit())
                }))
                .unwrap_or(false);
            if !ok {
                continue;
            }
            let Some(prop) = dav_child(stat, "prop") else {
                continue;
            };
            if let Some(name) = dav_child(prop, "displayname") {
                entry.display_name = name.text().unwrap_or("").trim().to_string();
            }
            if let Some(resource) = dav_child(prop, "resourcetype") {
                entry.is_directory = resource.children().any(|node| dav_tag(node, "collection"));
            }
            if let Some(length) = dav_child(prop, "getcontentlength") {
                entry.size = length.text().and_then(|value| value.trim().parse::<u64>().ok());
            }
        }
        result.push(entry);
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_namespaced_webdav() {
        let xml = r#"<?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/dav/</d:href>
            <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
          </d:response>
          <d:response>
            <d:href>/dav/My%20Movie.mkv</d:href>
            <d:propstat>
              <d:prop><d:displayname>My &amp; Movie</d:displayname>
                <d:getcontentlength>1234567</d:getcontentlength></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
            <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
              <d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>
          </d:response>
        </d:multistatus>"#;
        let parsed = parse_multistatus(xml).unwrap();
        assert_eq!(parsed.len(), 2);
        assert!(parsed[0].is_directory);
        assert_eq!(parsed[1].href, "/dav/My%20Movie.mkv");
        assert_eq!(parsed[1].display_name, "My & Movie");
        assert_eq!(parsed[1].size, Some(1_234_567));
        assert!(!parsed[1].is_directory);
    }

    #[test]
    fn rejects_incorrect_namespace_and_bad_xml() {
        assert!(parse_multistatus("<multistatus/>").is_err());
        assert!(parse_multistatus("<d:multistatus xmlns:d=\"DAV:\">").is_err());
        assert!(parse_multistatus("<!DOCTYPE x [<!ENTITY xx SYSTEM 'file:///etc/passwd'>]><d:multistatus xmlns:d=\"DAV:\"/>").is_err());
    }

    #[test]
    fn ignores_unrelated_nodes_and_missing_href() {
        let xml = r#"<multistatus xmlns="DAV:"><response/><response>
          <href>/dav/file.srt</href>
          <propstat><prop><getcontentlength>12</getcontentlength></prop>
          <status>HTTP/1.1 200 OK</status></propstat>
        </response></multistatus>"#;
        let rows = parse_multistatus(xml).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].size, Some(12));
    }
}
