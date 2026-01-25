import Foundation

package enum SQLiteLogStoreStorage: Sendable, Equatable {
    case inMemory
    case file(URL)
}
