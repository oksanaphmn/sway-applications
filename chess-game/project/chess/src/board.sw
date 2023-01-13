library board;

dep bitstack;
dep errors;
dep move;
dep piece;
dep special;
dep square;
dep utils;

use bitstack::BitStack;
use errors::*;
use move::Move;
use piece::{BLACK, Piece, WHITE};
use special::CastleRights;
use square::Square;
use utils::{compose, decompose, query_bit, set_bit, toggle_bit, multi_bit_mask, b256_multimask};
/**

note: for more detail about how pieces are encoded, see ./piece.sw

Initial board state:

    0011 0100 0010 0101 0110 0010 0100 0011
    0001 0001 0001 0001 0001 0001 0001 0001
    0000 0000 0000 0000 0000 0000 0000 0000
    0000 0000 0000 0000 0000 0000 0000 0000
    0000 0000 0000 0000 0000 0000 0000 0000
    0000 0000 0000 0000 0000 0000 0000 0000
    1001 1001 1001 1001 1001 1001 1001 1001
    1011 1100 1010 1101 1110 1010 1100 1011

4 bits per piece * 64 squares = 256 bits to store all pieces.
*/
// HEX equivalent of the above starting board state
pub const STARTING_POSITIONS: b256 = 0x34256243111111110000000000000000000000000000000099999999BCADEACB;
pub const STARTING_METADATA: u64 = 0b00000000_00000000_00000000_00000000_00001111_00000000_00000000_00000001;
pub const HALF_MOVE_MASK: u64 = 0x000000000000FF00;
pub const FULL_MOVE_MASK: u64 = 0x000000FF00000000;
pub const EN_PASSANT_MASK: u64 = 0x0000000000FF0000;
pub const CASTLING_MASK: u64 = 0x00000000FF000000;
pub const FULL_MOVE_MASK: u64 = 0x000000FF00000000;
pub const HALF_MOVE_CLEARING_MASK: u64 = 0xFFFFFFFFFFFF00FF;
pub const FULL_MOVE_CLEARING_MASK: u64 = 0xFFFFFF00FFFFFFFF;
pub const CASTLING_CLEARING_MASK: u64 = 0xFFFFFFFF00FFFFFF;
pub const EN_PASSANT_CLEARING_MASK: u64 = 0xFFFFFFFFFF00FFFF;

// struct for data transport
// replacement for FEN, unless can find way to encode all in single b256

// piecemap: b256
// metadata: u64,
// statehash: b256, ?



// struct for internal state representation.
// bitstacks are calculated from the piecemap
pub struct Board {
    piece_map: b256,
    bitstack: BitStack,
    metadata: u64,
}

impl Board {
    pub fn new() -> Board {
        Board {
            piece_map: STARTING_POSITIONS,
            bitstack: BitStack::new(),
            metadata: STARTING_METADATA,
        }
    }
}

impl Board {
    pub fn build(pieces: b256, bits: BitStack, data: u64) -> Board {
        Board {
            piece_map: pieces,
            bitstack: bits,
            metadata: data,
        }
    }
}

impl Board {
    pub fn clear_castling_rights(mut self) {
        self.metadata = self.metadata & CASTLING_CLEARING_MASK;
    }

    pub fn clear_en_passant(mut self) {
        self.metadata = self.metadata & EN_PASSANT_CLEARING_MASK;
    }

     // clear 1 nibble corresponding to a specific square's index from a piece_map
    pub fn clear_square(mut self, square: Square) {
        let mut index = square.to_index();
        // create a mask of all 1's except 4 0's on the target nibble.
        if index == 0 {
            let first_nibble_mask = b256_multimask(252);
            self.piece_map = self.piece_map & first_nibble_mask;
        } else {
            // eg: index = 42, * 4 = 168th bit
            // part 1: need 256 - 168 - 4 `1`s, << 168 + 4 bits.
            // part 2: need 168 `1`s
            // mask = part 1 | part 2
            let nibble_index = index * 4;
            // TODO: generate b256 mask for all bits except target nibble
            let mask_part_1 = b256_multimask((256 - (nibble_index) - 4) << nibble_index);
            let mask_part_2 = b256_multimask(nibble_index);
            self.piece_map = self.piece_map & (mask_part_1 | mask_part_2);
        }
    }
}

impl Board {
    pub fn half_move_counter(self) -> u64 {
        (self.metadata & HALF_MOVE_MASK) >> 8
    }

    pub fn full_move_counter(self) -> u64 {
        (self.metadata & FULL_MOVE_MASK) >> 32
    }

    pub fn en_passant_target(self) -> Square {
        Square::from_index((self.metadata & EN_PASSANT_MASK) >> 16).unwrap()
    }

    // TODO: consider partial reads, i.e: read only black castling rights if it's Blacks turn to move.
    pub fn castling_rights(self) -> Result<[CastleRights; 2], ChessError> {
        let value = (self.metadata & CASTLING_MASK) >> 24;
        match value {
            0x0 => Result::Ok([CastleRights::NoRights, CastleRights::NoRights]),
            0x1 => Result::Ok([CastleRights::NoRights, CastleRights::KingSide]),
            0x2 => Result::Ok([CastleRights::NoRights, CastleRights::QueenSide]),
            0x3 => Result::Ok([CastleRights::NoRights, CastleRights::Both]),
            0x4 => Result::Ok([CastleRights::KingSide, CastleRights::NoRights]),
            0x5 => Result::Ok([CastleRights::KingSide, CastleRights::KingSide]),
            0x6 => Result::Ok([CastleRights::KingSide, CastleRights::QueenSide]),
            0x7 => Result::Ok([CastleRights::KingSide, CastleRights::Both]),
            0x8 => Result::Ok([CastleRights::QueenSide, CastleRights::NoRights]),
            0x9 => Result::Ok([CastleRights::QueenSide, CastleRights::KingSide]),
            0xA => Result::Ok([CastleRights::QueenSide, CastleRights::QueenSide]),
            0xB => Result::Ok([CastleRights::QueenSide, CastleRights::Both]),
            0xC => Result::Ok([CastleRights::Both, CastleRights::NoRights]),
            0xD => Result::Ok([CastleRights::Both, CastleRights::KingSide]),
            0xE => Result::Ok([CastleRights::Both, CastleRights::QueenSide]),
            0xF => Result::Ok([CastleRights::Both, CastleRights::Both]),
            _ => Result::Err(ChessError::Unimplemented),
        }
    }

    pub fn set_castling_rights(mut self, rights: (CastleRights, CastleRights)) {
        self.clear_castling_rights();
        let value = match rights {
            (CastleRights::NoRights, CastleRights::NoRights) => 0x0,
            (CastleRights::NoRights, CastleRights::KingSide) => 0x1,
            (CastleRights::NoRights, CastleRights::QueenSide) => 0x2,
            (CastleRights::NoRights, CastleRights::Both) => 0x3,
            (CastleRights::KingSide, CastleRights::NoRights) => 0x4,
            (CastleRights::KingSide, CastleRights::KingSide) => 0x5,
            (CastleRights::KingSide, CastleRights::QueenSide) => 0x6,
            (CastleRights::KingSide, CastleRights::Both) => 0x7,
            (CastleRights::QueenSide, CastleRights::NoRights) => 0x8,
            (CastleRights::QueenSide, CastleRights::KingSide) => 0x9,
            (CastleRights::QueenSide, CastleRights::QueenSide) => 0xA,
            (CastleRights::QueenSide, CastleRights::Both) => 0xB,
            (CastleRights::Both, CastleRights::NoRights) => 0xC,
            (CastleRights::Both, CastleRights::KingSide) => 0xD,
            (CastleRights::Both, CastleRights::QueenSide) => 0xE,
            (CastleRights::Both, CastleRights::Both) => 0xF,
        };

        self.metadata = self.metadata | (value << 24);

    }

    pub fn reset_half_move(mut self) {
        self.metadata = self.metadata & HALF_MOVE_CLEARING_MASK;
    }

    pub fn clear_full_move(mut self) {
        self.metadata = self.metadata & FULL_MOVE_CLEARING_MASK;
    }

    // TODO: what about color in piece code?
    pub fn write_square_to_piecemap(mut self, color: u64, piece: Piece, dest: Square) {
        self.clear_square(dest);
        let mut index = dest.to_index();
        let mut piece_code = compose((0, 0, 0, (piece.to_u64())));

        if index == 0 {
            self.piece_map = self.piece_map | piece_code;
        } else {

        }
    }

    // TODO: move to Square::occupant() ?
    // needs the piece map though...
    pub fn read_square(self, square_index: u64) -> (u64, Piece) {
        let mut index = square_index;
        let mut mask = compose((0, 0, 0, multi_bit_mask(4)));
        let piece_code = if index == 0 {
            decompose(self.piece_map & mask).3
        } else {
            index *= 4;
            let mask = compose((0, 0, 0, multi_bit_mask(index) << index));
            decompose((self.piece_map & mask) >> index).3
        };
        let color = piece_code >> 4;
        let piece = Piece::from_u64(piece_code).unwrap();
        (color, piece)
    }
}

impl Board {


    // wraps Square::clear() & Square::set() ??                  REVIEW !
    pub fn move_piece(mut self, src: Square, dest: Square) {
        // let mut index_1 = src.to_index();
        // let mut index_2 = dest.to_index();
        // let piece_code = piece.to_u64();
        let (color, piece) = self.read_square(src.to_index());
        // clear src
        self.clear_square(src);
        // clear dest if !color
        self.clear_square(dest);
        // set src
        // TODO: add color
        self.write_square_to_piecemap(color, piece, dest);
    }

    pub fn side_to_move(self) -> u64 {
        query_bit(self.metadata, 0)
    }

    pub fn toggle_side_to_move(mut self) {
        self.metadata = toggle_bit(self.metadata, 0);
    }

    pub fn increment_half_move_counter(mut self) {
        let value = self.half_move_counter();
        self.reset_half_move();
        self.metadata = self.metadata | ((value + 1) << 8);
    }

    pub fn increment_full_move_counter(mut self) {
        let value = self.full_move_counter();
        self.clear_full_move();
        self.metadata = self.metadata | ((value + 1) << 32);
    }

    pub fn set_en_passant(mut self, target: Square) {
        self.clear_en_passant();
        self.metadata = self.metadata | target.to_index() << 16;
    }
}

impl Board {
    pub fn read_from_bitstack(board: Board) -> Board {
        // write piece_map, not sure about metadata yet...
        let board = Board::new();
        // loop over each index of bitstack, getting color and piece
        // set in piecemap with board.write_square_to_piecemap()
        let mut i = 0;
        while i < 64 {
            let bit = query_bit(board.bitstack.all.bits, i);

        }
        Board::new()
    }

    pub fn write_to_bitstack(self, board: Board) -> BitStack {
        let mut bitstack = BitStack::new();

        let mut s = 0;
        let mut i = 0;
        while i < 64 {
            let (color, piece) = board.read_square(s);
            if color == BLACK {
                match piece {
                    Piece::Pawn => bitstack.black_pawns.set_bit(i),
                    Piece::Bishop => bitstack.black_bishops.set_bit(i),
                    Piece::Rook => bitstack.black_rooks.set_bit(i),
                    Piece::Knight => bitstack.black_knights.set_bit(i),
                    Piece::Queen => bitstack.black_queen.set_bit(i),
                    Piece::King => bitstack.black_king.set_bit(i),
                }
            } else {
                match piece {
                    Piece::Pawn => bitstack.white_pawns.set_bit(i),
                    Piece::Bishop => bitstack.white_bishops.set_bit(i),
                    Piece::Rook => bitstack.white_rooks.set_bit(i),
                    Piece::Knight => bitstack.white_knights.set_bit(i),
                    Piece::Queen => bitstack.white_queen.set_bit(i),
                    Piece::King => bitstack.white_king.set_bit(i),
                }
            };
            s += 4;
            i += 1;
        }

        bitstack
    }


    // TODO: consider making this a method on Board
    // this method assumes that the Board and the Move have already been validated !
    pub fn transition(mut self, move: Move) {
        // update metadata:
        self.toggle_side_to_move();
        let turn =
        self.increment_half_move_counter();
        let half_move = self.half_move_counter();
        if  half_move > 0 && half_move % 2 == 0 {
            self.increment_full_move_counter();
        };
        // update en_passant if needed
        if move.dest.to_index() == self.en_passant_target().to_index() {
            self.clear_en_passant();
        };

        /**
        let (allowed, maybe_square) = move.allows_en_passant();
        if allowed {
            self.set_en_passant(maybe_square.unwrap())
        }
        */

        /**
        // update castling_rights if needed
        if move.is_castling() {
            let mut rights = self.castling_rights();
            let whose_turn = self.side_to_move();
            match whose_turn {
                Colour::Black => {
                    self.set_castling_rights((CastleRights::NoRights, rights[1].unwrap()));
                },
                Coulour::White => {
                    self.set_castling_rights((rights[0].unwrap(), CastleRights::NoRights));
                },
            };
        }
        */

        // these are likely needed in validate_move()
        // let mut bitstack = self.generate_bitstack();
        // self.write_piece_map(bitstack);

        /**
        // read the piece on src square
        let piece = self.square(move.source);
        // set the piece on dest and clear src
        self.move_piece(move.src, move.dest, color, piece);
        */




    }

    pub fn set_castling_rights(mut self, rights: (CastleRights, CastleRights)) {
        self.clear_castling_rights();
        let value = match rights {
            (CastleRights::NoRights, CastleRights::NoRights) => 0x0,
            (CastleRights::NoRights, CastleRights::KingSide) => 0x1,
            (CastleRights::NoRights, CastleRights::QueenSide) => 0x2,
            (CastleRights::NoRights, CastleRights::Both) => 0x3,
            (CastleRights::KingSide, CastleRights::NoRights) => 0x4,
            (CastleRights::KingSide, CastleRights::KingSide) => 0x5,
            (CastleRights::KingSide, CastleRights::QueenSide) => 0x6,
            (CastleRights::KingSide, CastleRights::Both) => 0x7,
            (CastleRights::QueenSide, CastleRights::NoRights) => 0x8,
            (CastleRights::QueenSide, CastleRights::KingSide) => 0x9,
            (CastleRights::QueenSide, CastleRights::QueenSide) => 0xA,
            (CastleRights::QueenSide, CastleRights::Both) => 0xB,
            (CastleRights::Both, CastleRights::NoRights) => 0xC,
            (CastleRights::Both, CastleRights::KingSide) => 0xD,
            (CastleRights::Both, CastleRights::QueenSide) => 0xE,
            (CastleRights::Both, CastleRights::Both) => 0xF,
        };

        self.metadata = self.metadata | (value << 24);

    }

    pub fn reset_half_move(mut self) {
        self.metadata = self.metadata & HALF_MOVE_CLEARING_MASK;
    }

    pub fn clear_full_move(mut self) {
        self.metadata = self.metadata & FULL_MOVE_CLEARING_MASK;
    }
}

impl Board {
    pub fn piece(self, square: Square) -> (u64, Piece) {
        let mut index = square.to_index();
        let mut mask = compose((0, 0, 0, multi_bit_mask(4)));
        let piece_code = if index == 0 {
            decompose(self.piecemap & mask).3
        } else {
            index *= 4;
            let mask = compose((0, 0, 0, multi_bit_mask(index) << index));
            decompose((self.piecemap & mask) >> index).3
        };
        let colour = piece_code >> 4;
        let piece = Piece::from_u64(piece_code).unwrap();
        (colour, piece)
    }

    pub fn side_to_move(self) -> u64 {
        query_bit(self.metadata, 0)
    }

    pub fn toggle_side_to_move(mut self) {
        self.metadata = toggle_bit(self.metadata, 0);
    }

    pub fn increment_half_move_counter(mut self) {
        let value = self.half_move_counter();
        self.reset_half_move();
        self.metadata = self.metadata | ((value + 1) << 8);
    }

    pub fn increment_full_move_counter(mut self) {
        let value = self.full_move_counter();
        self.clear_full_move();
        self.metadata = self.metadata | ((value + 1) << 32);
    }

    pub fn set_en_passant(mut self, target: Square) {
        self.clear_en_passant();
        self.metadata = self.metadata | target.to_index() << 16;
    }

    pub fn generate_bitstack(self) -> BitStack {
        BitStack::new()
    }
    pub fn write_piecemap(self, bitstack: BitStack) {

    }
}

impl Board {
    // TODO: consider making this a method on Board
    // this method assumes that the Board and the Move have already been validated !
    pub fn transition(mut self, move: Move) {
        // update metadata:
        self.toggle_side_to_move();
        let turn =
        self.increment_half_move_counter();
        let half_move = self.half_move_counter();
        if  half_move > 0 && half_move % 2 == 0 {
            self.increment_full_move_counter();
        };
        // update en_passant if needed
        if move.dest.to_index() == self.en_passant_target().to_index() {
            self.clear_en_passant();
        };

        /**
        let (allowed, maybe_square) = move.allows_en_passant();
        if allowed {
            self.set_en_passant(maybe_square.unwrap())
        }
        */

        /**
        // update castling_rights if needed
        if move.is_castling() {
            let mut rights = self.castling_rights();
            let whose_turn = self.side_to_move();
            match whose_turn {
                Colour::Black => {
                    self.set_castling_rights((CastleRights::NoRights, rights[1].unwrap()));
                },
                Coulour::White => {
                    self.set_castling_rights((rights[0].unwrap(), CastleRights::NoRights));
                },
            };
        }
        */

        // these are likely needed in validate_move()
        // let mut bitstack = self.generate_bitstack();
        // self.write_piecemap(bitstack);

        /**
        // read the piece on src square
        let piece = self.square(move.source);
        // set the piece on dest and clear src
        self.move_piece(move.src, move.dest, piece);
        */




    }
}

//////////////////////////////////////////////////////////////////
/// TESTS
//////////////////////////////////////////////////////////////////
#[test()]
fn test_new_board() {
    let board = Board::new();
    assert(board.piece_map == STARTING_POSITIONS);
    assert(board.metadata == STARTING_METADATA);
}

#[test()]
fn test_transition_side_to_move() {
    let mut p1 = Board::build(STARTING_POSITIONS, BitStack::new(), STARTING_METADATA);
    let m1 = Move::build(Square::a3, Square::a4, Option::None);
    p1.transition(m1);
    assert(p1.side_to_move() == BLACK);
    let m2 = Move::build(Square::a2, Square::a3, Option::None);
    p1.transition(m2);
    assert(p1.side_to_move() == WHITE);
}

#[test()]
fn test_transition_half_move_increment() {
    let mut p1 = Board::build(STARTING_POSITIONS, BitStack::new(),STARTING_METADATA);
    let m1 = Move::build(Square::a2, Square::a3, Option::None);
    p1.transition(m1);
    assert(p1.half_move_counter() == 1);
}

#[test()]
fn test_increment_full_move_counter() {
    let metadata = 0b00000000_00000000_00000000_00000000_00001111_00000000_00000000_00000001;
    let mut p1 = Board::build(STARTING_POSITIONS, BitStack::new(), metadata);
    let m1 = Move::build(Square::a2, Square::a3, Option::None);

    p1.transition(m1);
    assert(p1.half_move_counter() == 1);
    assert(p1.full_move_counter() == 0);
    p1.transition(m1);
    assert(p1.half_move_counter() == 2);
    assert(p1.full_move_counter() == 1);
    p1.transition(m1);
    assert(p1.half_move_counter() == 3);
    assert(p1.full_move_counter() == 1);
    p1.transition(m1);
    assert(p1.half_move_counter() == 4);
    assert(p1.full_move_counter() == 2);
}

#[test()]
fn test_increment_half_move_counter() {
    let mut p1 = Board::new();
    assert(p1.half_move_counter() == 0);
    p1.increment_half_move_counter();
    assert(p1.half_move_counter() == 1);
}
