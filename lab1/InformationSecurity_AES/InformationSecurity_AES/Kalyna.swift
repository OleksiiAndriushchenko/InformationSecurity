//
//  Kalyna.swift
//  InformationSecurity_AES
//
//  Created by Oleksii Andriushchenko on 05.10.2020.
//

import Foundation

final class KalynaAlgorithm {

  struct Config {
    // 128, 256, 512
    let blockSize: Int
    // 128, 256, 512
    let keyLength: Int
    let rounds: Int
    let rows: Int

    static var config1: Config {
      return .init(blockSize: 128, keyLength: 128, rounds: 10, rows: 2)
    }

    static var config2: Config {
      return .init(blockSize: 128, keyLength: 256, rounds: 14, rows: 2)
    }

    static var config3: Config {
      return .init(blockSize: 256, keyLength: 256, rounds: 14, rows: 4)
    }

    static var config4: Config {
      return .init(blockSize: 256, keyLength: 512, rounds: 18, rows: 4)
    }

    static var config5: Config {
      return .init(blockSize: 512, keyLength: 512, rounds: 18, rows: 8)
    }
  }

  private let config: Config
  // rounds x rows x columns
  private var keys: [[[UInt8]]] = []
  private lazy var vConstant: [UInt8] = Array(0..<config.rows).flatMap { _ in [0x01, 0x00, 0x01, 0x00, 0x01, 0x00, 0x01, 0x00] }

  init(key: String, config: Config = .config1) {
    self.config = config
    self.keys = keyExpansion(key: key.data(using: .utf8)!.map { $0 })
  }

  init(key: Data, config: Config = .config1) {
    self.config = config
    self.keys = keyExpansion(key: key.map { $0 })
  }

  func encode(text: String) -> Data {
    guard let data = text.data(using: .utf8) else {
      fatalError("Can't get data from input text")
    }

    return encode(data: data)
  }

  func encode(data: Data) -> Data {
    var iter = 0
    var result = Data()
    while 16 * (iter + 1) <= data.count  {
      do {
        let output = try encodeBlock(input: data[(16 * iter)..<(16 * (iter + 1))])
        result.append(output)
      } catch {
        fatalError(error.localizedDescription)
      }

      iter += 1
    }

    return result
  }

  func decode(data: Data) -> String {
    return String(data: decode(data: data), encoding: .utf8)!
  }

  func decode(data: Data) -> Data {
    var iter = 0
    var result = Data()
    while 16 * (iter + 1) <= data.count  {
      do {
        let output = try decodeBlock(input: Data(Array(data[(16 * iter)..<(16 * (iter + 1))])))
        result.append(output)
      } catch {
        fatalError(error.localizedDescription)
      }

      iter += 1
    }

    return result
  }

  // MARK: Encode

  private func encodeBlock(input: Data) throws -> Data {
    guard input.count == config.blockSize / 8 else {
      throw AESError.badInput("Input should be exactly \(config.blockSize) bits")
    }

    var state = createTable(from: input.map { $0 })
    print("Start")
    printTable(table: state)
    addModulo2in64(state: &state, key: keys[0])

    for round in 1..<config.rounds {
      subBytes(state: &state)
      shiftRows(state: &state)
      linearTransformation(state: &state)
      addModulo2(state: &state, key: keys[round])
    }

    subBytes(state: &state)
    shiftRows(state: &state)
    linearTransformation(state: &state)
    addModulo2in64(state: &state, key: keys[config.rounds])

    print("End")
    printTable(table: state)

    let output = createOutput(from: state)
    return output
  }

  private func addModulo2in64(state: inout [[UInt8]], key: [[UInt8]]) {
    for (index, row) in state.enumerated() {
      state[index] = add(lhs: row, rhs: key[index])
    }
  }

  private func add(lhs: [UInt8], rhs: [UInt8]) -> [UInt8] {
    var result: [UInt8] = []
    var isOverflow = false
    zip(lhs, rhs).forEach { left, right in
      let (value, overflow) = left.addingReportingOverflow(right)
      result.append(isOverflow ? value + 1 : value)
      isOverflow = overflow
    }
    return result
  }

  private func subBytes(state: inout [[UInt8]]) {
    for row in 0..<state.count {
      for column in 0..<state[row].count {
        state[row][column] = kalynaBoxes[column % 4][Int(state[row][column])]
      }
    }
  }

  private func shiftRows(state: inout [[UInt8]]) {
    for columnIndex in 0..<8 {
      let shift = (columnIndex * config.blockSize) / 512
      let column = state.map { $0[columnIndex] }.shifted(by: shift)
      for row in 0..<state.count {
        state[row][columnIndex] = column[row]
      }
    }
  }

  private func linearTransformation(state: inout [[UInt8]]) {
    let vector: [UInt8] = [1, 1, 5, 1, 8, 6, 7, 4]
    let copy = state
    for column in 0..<8 {
      let shiftedVector = vector.shifted(by: 8 - column)
      for (rowIndex, row) in copy.enumerated() {
        state[rowIndex][column] = scalarProdcut(lhs: shiftedVector, rhs: row)
      }
    }
  }

  private func scalarProdcut(lhs: [UInt8], rhs: [UInt8]) -> UInt8 {
    return zip(lhs, rhs).reduce(0, { $0 ^ multiply(lhs: $1.0, rhs: $1.1) })
  }

  private func multiply(lhs: UInt8, rhs: UInt8) -> UInt8 {
    var result: UInt8 = 0
    var left = UInt8(lhs)
    var right = UInt8(rhs)
    while left > 0 && right > 0 {
      if right & 1 != 0 {
        result ^= left
      }

      if left & 0x80 != 0 {
        left = (left << 1) ^ 0x1d
      } else {
        left <<= 1
      }
      right >>= 1
    }
    return UInt8(result)
  }

  private func addModulo2(state: inout [[UInt8]], key: [[UInt8]]) {
    for row in 0..<state.count {
      for column in 0..<state[0].count {
        state[row][column] ^= key[row][column]
      }
    }
  }

  private func createOutput(from state: [[UInt8]]) -> Data {
    return Data(state.flatMap { $0 })
  }

  // MARK: - Decode

  private func decodeBlock(input: Data) throws -> Data {
    guard input.count == 16 else {
      throw AESError.badInput("Input should be exactly 16 bytes")
    }

    var state = createTable(from: input.map { $0 })
    substractModulo2in64(state: &state, key: keys[config.rounds])
    invLinearTransformation(state: &state)
    invShiftRows(state: &state)
    invSubBytes(state: &state)

    for round in 1..<Constants.Nr {
      let invRound = Constants.Nr - round
      addModulo2(state: &state, key: keys[invRound])
      invLinearTransformation(state: &state)
      invShiftRows(state: &state)
      invSubBytes(state: &state)
    }

    substractModulo2in64(state: &state, key: keys[0])
    print("End")
    printTable(table: state)

    let output = createOutput(from: state)
    return output
  }

  private func substractModulo2in64(state: inout [[UInt8]], key: [[UInt8]]) {
    for (index, row) in state.enumerated() {
      state[index] = substract(lhs: row, rhs: key[index])
    }
  }

  private func substract(lhs: [UInt8], rhs: [UInt8]) -> [UInt8] {
    var result: [UInt8] = []
    var isOverflow = false
    zip(lhs, rhs).forEach { left, right in
      let (value, overflow) = left.subtractingReportingOverflow(isOverflow ? right + 1 : right)
      result.append(value)
      isOverflow = overflow
    }
    return result
  }

  private func invSubBytes(state: inout [[UInt8]]) {
    for row in 0..<state.count {
      for column in 0..<state[row].count {
        state[row][column] = invKalynaBoxes[column % 4][Int(state[row][column])]
      }
    }
  }

  private func invShiftRows(state: inout [[UInt8]]) {
    for columnIndex in 0..<8 {
      let shift = (columnIndex * config.blockSize) / 512
      let column = state.map { $0[columnIndex] }.shifted(by: shift)
      for row in 0..<state.count {
        state[row][columnIndex] = column[row]
      }
    }
  }

  private func invLinearTransformation(state: inout [[UInt8]]) {
    let vector: [UInt8] = [0xad, 0x95, 0x76, 0xa8, 0x2f, 0x49, 0xd7, 0xca]
    let copy = state
    for column in 0..<8 {
      let shiftedVector = vector.shifted(by: 8 - column)
      for (rowIndex, row) in copy.enumerated() {
        state[rowIndex][column] = scalarProdcut(lhs: shiftedVector, rhs: row)
      }
    }
  }

  // MARK: - Key expansion

  private func keyExpansion(key: [UInt8]) -> [[[UInt8]]] {
    let intermediateKey = createIntermediateKey()

    var keys: [[[UInt8]]] = []

    for index in 0...config.rounds {
      if index % 2 == 0 {
        keys.append(createEvenKey(key: key, intermediateKey: intermediateKey, index: index))
      } else {
        keys.append(createOddKey(key: keys.last!))
      }
    }

    return keys
  }

  private func createEvenKey(key: [UInt8], intermediateKey: [[UInt8]], index: Int) -> [[UInt8]] {
    var initialKey: [[UInt8]] = {
      if config.blockSize == config.keyLength {
        return createTable(from: key.shifted(by: 4 * index).map { $0 })
      } else {
        return createTable(from: key.map { $0 })
      }
    }()

    let phiValue = phiFunction(key: intermediateKey, index: index)
    addModulo2in64(state: &initialKey, key: phiValue)
    subBytes(state: &initialKey)
    shiftRows(state: &initialKey)
    linearTransformation(state: &initialKey)
    addModulo2(state: &initialKey, key: phiValue)
    subBytes(state: &initialKey)
    shiftRows(state: &initialKey)
    linearTransformation(state: &initialKey)
    addModulo2in64(state: &initialKey, key: phiValue)

    return initialKey
  }

  private func createOddKey(key: [[UInt8]]) -> [[UInt8]] {
    let row = key.flatMap { $0 }
    return createTable(from: row.shifted(by: (config.blockSize / 4 + 24) / 8))
  }

  private func createIntermediateKey() -> [[UInt8]] {
    let keyAlpha = Array(
      [
        Array(key[0..<(key.count / 2)]),
        Array(key[(key.count / 2)..<key.count])
      ]
    )
    let keyOmega = Array(
      [
        Array(key[0..<(key.count / 2)]),
        Array(key[(key.count / 2)..<key.count])
      ]
    )

    var interKey = createInititalIntermediateKey()
    addModulo2in64(state: &interKey, key: keyAlpha)
    subBytes(state: &interKey)
    shiftRows(state: &interKey)
    linearTransformation(state: &interKey)
    addModulo2(state: &interKey, key: keyOmega)
    subBytes(state: &interKey)
    shiftRows(state: &interKey)
    linearTransformation(state: &interKey)
    addModulo2in64(state: &interKey, key: keyAlpha)
    subBytes(state: &interKey)
    shiftRows(state: &interKey)
    linearTransformation(state: &interKey)

    return interKey
  }

  private func createInititalIntermediateKey() -> [[UInt8]] {
    var key: [[UInt8]] = []
    for _ in 0..<config.rows {
      key.append([UInt8](repeating: 0, count: 8))
    }
    let firstByte: UInt8 = UInt8((config.blockSize + config.keyLength + 64) / 64)
    key[0][0] = firstByte
    return key
  }

  private func printTable(table: [[UInt8]]) {
    let text = table.map { row -> String in
      return row.map { String(format: "%02x", $0) }.joined()
    }.joined()
    print("Table: \(text)")
  }

  private func createTable(from key: [UInt8]) -> [[UInt8]] {
    let count = key.count / 8
    var result: [[UInt8]] = []
    for index in 0..<count {
      result.append(Array(key[(8 * index)..<(8 * (index + 1))]))
    }
    return result
  }

  private func phiFunction(key: [[UInt8]], index: Int) -> [[UInt8]] {
    let shiftedConstant = vConstant.map { $0 << (index / 2) }
    var table = createTable(from: shiftedConstant)
    addModulo2in64(state: &table, key: key)
    return table
  }
}