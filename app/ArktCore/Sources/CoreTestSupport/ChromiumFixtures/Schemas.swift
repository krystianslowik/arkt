import Foundation

typealias FixtureColumn = FixtureDatabase.Column

enum HistorySchema {
  static let urls: [FixtureColumn] = [
    .init(name: "id", type: "INTEGER"),
    .init(name: "url", type: "LONGVARCHAR"),
    .init(name: "title", type: "LONGVARCHAR"),
    .init(name: "visit_count", type: "INTEGER", defaultSQL: "0 NOT NULL"),
    .init(name: "typed_count", type: "INTEGER", defaultSQL: "0 NOT NULL"),
    .init(name: "last_visit_time", type: "INTEGER NOT NULL"),
    .init(name: "hidden", type: "INTEGER", defaultSQL: "0 NOT NULL"),
  ]

  static let visits: [FixtureColumn] = [
    .init(name: "id", type: "INTEGER"),
    .init(name: "url", type: "INTEGER NOT NULL"),
    .init(name: "visit_time", type: "INTEGER NOT NULL"),
    .init(name: "from_visit", type: "INTEGER"),
    .init(name: "transition", type: "INTEGER", defaultSQL: "0 NOT NULL"),
    .init(name: "segment_id", type: "INTEGER"),
    .init(name: "visit_duration", type: "INTEGER", defaultSQL: "0 NOT NULL"),
    .init(name: "incremented_omnibox_typed_score", type: "BOOLEAN", defaultSQL: "FALSE NOT NULL"),
  ]
}

enum LoginsSchema {
  static let logins: [FixtureColumn] = [
    .init(name: "origin_url", type: "VARCHAR NOT NULL"),
    .init(name: "action_url", type: "VARCHAR"),
    .init(name: "username_element", type: "VARCHAR"),
    .init(name: "username_value", type: "VARCHAR"),
    .init(name: "password_element", type: "VARCHAR"),
    .init(name: "password_value", type: "BLOB"),
    .init(name: "submit_element", type: "VARCHAR"),
    .init(name: "signon_realm", type: "VARCHAR NOT NULL"),
    .init(name: "date_created", type: "INTEGER NOT NULL"),
    .init(name: "blacklisted_by_user", type: "INTEGER NOT NULL"),
    .init(name: "scheme", type: "INTEGER NOT NULL"),
    .init(name: "password_type", type: "INTEGER"),
    .init(name: "times_used", type: "INTEGER"),
    .init(name: "date_last_used", type: "INTEGER", defaultSQL: "0"),
    .init(name: "date_password_modified", type: "INTEGER", defaultSQL: "0"),
  ]
}

enum CookiesSchema {
  static let cookies: [FixtureColumn] = [
    .init(name: "creation_utc", type: "INTEGER NOT NULL"),
    .init(name: "host_key", type: "TEXT NOT NULL"),
    .init(name: "top_frame_site_key", type: "TEXT NOT NULL", defaultSQL: "''"),
    .init(name: "name", type: "TEXT NOT NULL"),
    .init(name: "value", type: "TEXT NOT NULL", defaultSQL: "''"),
    .init(name: "encrypted_value", type: "BLOB NOT NULL", defaultSQL: "''"),
    .init(name: "path", type: "TEXT NOT NULL"),
    .init(name: "expires_utc", type: "INTEGER NOT NULL"),
    .init(name: "is_secure", type: "INTEGER NOT NULL"),
    .init(name: "is_httponly", type: "INTEGER NOT NULL"),
    .init(name: "last_access_utc", type: "INTEGER NOT NULL"),
    .init(name: "has_expires", type: "INTEGER NOT NULL", defaultSQL: "1"),
    .init(name: "is_persistent", type: "INTEGER NOT NULL", defaultSQL: "1"),
    .init(name: "priority", type: "INTEGER NOT NULL", defaultSQL: "1"),
    .init(name: "samesite", type: "INTEGER NOT NULL", defaultSQL: "-1"),
    .init(name: "source_scheme", type: "INTEGER NOT NULL", defaultSQL: "0"),
    .init(name: "source_port", type: "INTEGER NOT NULL", defaultSQL: "-1"),
    .init(name: "last_update_utc", type: "INTEGER NOT NULL", defaultSQL: "0"),
    .init(name: "source_type", type: "INTEGER NOT NULL", defaultSQL: "0"),
    .init(name: "has_cross_site_ancestor", type: "INTEGER NOT NULL", defaultSQL: "0"),
  ]
}
