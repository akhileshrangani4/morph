import Foundation

/// Local credentials for this throwaway demo build.
///
/// This file is committed with empty values and marked `skip-worktree` on the
/// demo machine, so real keys can sit here without ever reaching a commit.
/// To fill it in on a fresh clone:
///
///     git update-index --skip-worktree Morph/Secrets.swift
///
/// then paste your values below. Anything left empty falls back to the keys
/// pasted into the app's settings sheet at runtime.
enum Secrets {
    static let openAIKey = ""
    static let charmingToken = ""
}
