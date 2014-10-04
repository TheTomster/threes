# Threes!

require 'set'

# The board holds the pieces in specific locations. It's a 4x4 grid.
class Board
  SIZE = 4
  INITIAL = 9
  def initialize(bag)
    @pieces = []
    @pieces += bag.take(INITIAL)
    @pieces += Array.new(SIZE * SIZE - INITIAL)
    @pieces.shuffle!
  end

  def index(row, column)
    row * SIZE + column
  end
  private :index

  def [](row, column)
    @pieces[index(row, column)]
  end

  def []=(row, column, value)
    @pieces[index(row, column)] = value
  end
  private :[]=

  def size
    SIZE
  end

  def empty?(row, column)
    self[row, column].nil?
  end

  def merge!(sr, sc, dr, dc)
    p = self[sr, sc]
    d = self[dr, dc]
    self[dr, dc] = p.merge(d)
    self[sr, sc] = nil
  end

  def move!(sr, sc, dr, dc)
    if empty?(dr, dc)
      self[dr, dc] = self[sr, sc]
      self[sr, sc] = nil
    elsif self[sr, sc].merges?(self[dr, dc])
      merge!(sr, sc, dr, dc)
    else
      fail "Invalid move attempt: #{sr} #{sc} -> #{dr} #{dc}"
    end
  end

  def rotate_ccw_once!
    copy = @pieces.dup
    (0...size).each do |row|
      (0...size).each do |column|
        didx = index(size - 1 - column, row)
        self[row, column] = copy[didx]
      end
    end
    self
  end

  def rotate_ccw!(turns)
    turns.times { rotate_ccw_once! }
    self
  end

  def rotate_cw!(turns)
    turns = 4 - turns
    turns.times { rotate_ccw_once! }
    self
  end
end

# Serves up random pieces.
class Bag
  def initialize
    fill
  end

  def fill
    @bag = [
      Piece.new(1), Piece.new(1), Piece.new(2), Piece.new(2), Piece.new(3),
      Piece.new(3)
    ]
    randoms = @bag.dup.shuffle
    @bag += randoms.take(3)
    @bag.shuffle!
  end
  private :fill

  def each
    return enum_for(:each) unless block_given?
    loop do
      fill if @bag.empty?
      yield @bag.pop
    end
  end

  include Enumerable
end

# A piece on the game board.
class Piece
  attr_reader :value, :merge_value

  def initialize(value)
    @value = value
    case value
    when 1
      @merge_value = 2
    when 2
      @merge_value = 1
    else
      @merge_value = value
    end
  end

  def merges?(other)
    return true if other.nil?
    other.value == merge_value
  end

  def merge(_other)
    if value == 1 || value == 2
      Piece.new(3)
    else
      Piece.new(value * 2)
    end
  end
end

# Slides pieces around on the board.
class Slider
  attr_reader :lifted

  def initialize
    @lifted = Set.new
    @moved = Set.new
  end

  TURNS = { up: 0, left: 1, down: 2, right: 3 }
  def turns(direction)
    TURNS[direction]
  end
  private :turns

  def dest(board, row, column)
    board[row - 1, column]
  end
  private :dest

  def merges?(s, d)
    s.merges?(d)
  end
  private :merges?

  def can_lift?(board, row, column)
    p = board[row, column]
    d = dest(board, row, column)
    return false if p.nil?
    d.nil? || merges?(p, d)
  end
  private :can_lift?

  def lift!(board, row, column)
    board.move!(row, column, row - 1, column)
  end
  private :lift!

  def lift_column!(board, column)
    (1...board.size).each do |row|
      next unless can_lift?(board, row, column)
      lift!(board, row, column)
      @lifted << column
    end
  end
  private :lift_column!

  def slide!(board, direction)
    board.rotate_ccw!(turns(direction))
    (0...board.size).each do |column|
      lift_column!(board, column)
    end
    board.rotate_cw!(turns(direction))
  end
end

# The terminal. Updates what the user sees.
class Screen
  RED = "\x1B[31m"
  BLUE = "\x1B[36m"
  RESET = "\x1B[0m"

  def update(board)
    clear
    draw(board)
    welcome
  end

  def welcome
    puts
    puts "#{RED}T #{BLUE}H #{RESET}R E E S"
    puts <<EOF
Use arrow keys to slide pieces. Merge them together to make larger numbers!
Press `q` to quit.
EOF
  end

  def clear
    print "\x1B[2J\x1B[H"
  end

  def center(s)
    str = s.to_s
    str = ' ' + str if str.length.odd?
    diff = 4 - str.length
    pad = diff / 2
    ' ' * pad << str << ' ' * pad
  end

  def draw_piece(p)
    if p.nil?
      print center('--')
    else
      print BLUE if p.value == 1
      print RED if p.value == 2
      print center(p.value)
      print RESET
    end
  end

  def draw(board)
    (0...board.size).each do |r|
      (0...board.size).each do |c|
        p = board[r, c]
        draw_piece(p)
        print '   '
      end
      print "\n\n"
    end
  end
end

# Read input from terminal
module Input
  ARROWS = {
    "\e[A" => :up,
    "\e[D" => :left,
    "\e[C" => :right,
    "\e[B" => :down
  }

  def self.if_avail(&block)
    block.call
  rescue
    ''
  end

  def self.raw_char
    input = STDIN.getc.chr
    if input == "\e"
      input << if_avail { STDIN.read_nonblock(3) }
      input << if_avail { STDIN.read_nonblock(2) }
    end
    input
  end

  def self.raw!
    STDIN.echo = false
    STDIN.raw!
  end

  def self.cooked!
    STDIN.echo = true
    STDIN.cooked!
  end

  def self.with_raw(&block)
    raw!
    block.call
  ensure
    cooked!
  end

  def self.next
    with_raw do
      c = raw_char
      return :quit if c == 'q'
      dir = ARROWS[c]
      redo if dir.nil?
      dir
    end
  end
end

# Main game controller
class Game
  attr_reader :bag, :board, :screen, :input

  def initialize
    @bag = Bag.new
    @board = Board.new(bag)
    @screen = Screen.new
  end

  def mainloop
    loop do
      @screen.update(board)
      command = Input.next
      puts "command: #{command}"
      break if command == :quit
      slider = Slider.new
      slider.slide!(board, command)
    end
  end
end
