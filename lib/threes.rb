# Threes!
# Copyright (c) 2014 Tom Wright
# Distributed under GPLv2, see LICENSE for details.
# Original by Asher Vollmer and Greg Wohlwend. <http://asherv.com/threes/>
# Support their work and buy the game!

require 'io/console'
require 'set'

# The board holds the pieces in specific locations. It's a 4x4 grid.
class Board
  SIZE = 4
  INITIAL = 9
  def initialize(bag)
    @bag = bag
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
    @bag.merged(self[dr, dc].value)
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

  def each(&block)
    return enum_for(:each) unless block_given?
    @pieces.each(&block)
  end
end

# Serves up random pieces.
class Bag
  attr_reader :extras, :max
  def initialize
    @extras = [1, 1, 2, 2, 3, 3].map { |val| Piece.new(val) }
    @max = 3
    fill
  end

  def fill
    @bag = [
      Piece.new(1), Piece.new(1), Piece.new(2), Piece.new(2), Piece.new(3),
      Piece.new(3)
    ]
    randoms = extras.shuffle
    @bag += randoms.take(3)
    @bag.shuffle!
  end
  private :fill

  def next
    ret = peek
    @bag = @bag.drop(1)
    ret
  end

  def take(n)
    ret = []
    n.times { ret << self.next }
    ret
  end

  def peek
    fill if @bag.empty?
    @bag.first
  end

  def merged(value)
    return if value < max
    @max = value
    @extras << Piece.new(value / 8) if value >= 48
  end

  include Enumerable
end

# A piece on the game board.
class Piece
  MAX_VALUE = 6144

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
    return false if value >= MAX_VALUE
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
  attr_reader :lifted, :board, :bag

  def initialize(board, bag)
    @lifted = Set.new
    @board = board
    @bag = bag
  end

  TURNS = { up: 0, left: 1, down: 2, right: 3 }
  def turns(direction)
    TURNS[direction]
  end
  private :turns

  def dest(row, column)
    board[row - 1, column]
  end
  private :dest

  def merges?(s, d)
    s.merges?(d)
  end
  private :merges?

  def can_lift?(row, column)
    p = board[row, column]
    d = dest(row, column)
    return false if p.nil?
    d.nil? || merges?(p, d)
  end
  private :can_lift?

  def lift!(row, column)
    board.move!(row, column, row - 1, column)
  end
  private :lift!

  def lift_column!(column)
    (1...board.size).each do |row|
      next unless can_lift?(row, column)
      lift!(row, column)
      lifted << column
    end
  end
  private :lift_column!

  def spawn!
    return if lifted.empty?
    spawn_col = lifted.to_a.sample
    p = bag.next
    board[board.size - 1, spawn_col] = p
  end

  def slide!(direction)
    board.rotate_ccw!(turns(direction))
    (0...board.size).each do |column|
      lift_column!(column)
    end
    spawn!
  ensure
    board.rotate_cw!(turns(direction))
  end

  def can_move?(direction)
    board.rotate_ccw!(turns(direction))
    (0...board.size).each do |column|
      (1...board.size).each do |row|
        return true if can_lift?(row, column)
      end
    end
    return false
  ensure
    board.rotate_cw!(turns(direction))
  end

  def no_moves?
    [:up, :down, :left, :right].each do |direction|
      return false if can_move?(direction)
    end
    true
  end
end

# The terminal. Updates what the user sees.
class Screen
  BOLD = "\e[1m"
  RED = "\e[31m"
  BLUE = "\e[36m"
  RESET = "\e[0m"

  def update(board, bag)
    clear
    draw(board)
    bag_preview(bag)
    welcome
  end

  def bag_preview(bag)
    p = bag.peek
    color = nil
    color = BLUE if p.value == 1
    color = RED if p.value == 2
    v = p.value.to_s
    v = '+' if p.value > 3
    puts "Next: #{color}#{v}#{RESET}"
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
    print "\e[2J\e[H"
  end

  def center(s)
    str = s.to_s
    str = ' ' + str if str.length.odd?
    diff = 4 - str.length
    pad = diff / 2
    ' ' * pad << str << ' ' * pad
  end

  def max_value?(board, v)
    board.each do |p|
      next if p.nil?
      return false if p.value > v
    end
    true
  end

  def draw_piece(board, p)
    if p.nil?
      print center('--')
    else
      print BLUE if p.value == 1
      print RED if p.value == 2
      print BOLD if max_value?(board, p.value)
      print center(p.value)
    end
  ensure
    print RESET
  end

  def draw(board)
    (0...board.size).each do |r|
      (0...board.size).each do |c|
        p = board[r, c]
        draw_piece(board, p)
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

# Computes the score of a board.
class Score
  attr_reader :points

  def initialize(board)
    @points = 0
    board.each do |p|
      next if p.nil?
      val = p.value
      next if val == 1 || val == 2
      @points += score(val)
    end
  end

  def score(value)
    3**(Math.log2(value / 3) + 1)
  end

  def to_s
    @points.to_i.to_s
  end
end

class UserQuit < Exception
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
      screen.update(board, bag)
      slider = Slider.new(board, bag)
      if slider.no_moves?
        game_over
        break
      end
      handle_input(slider)
    end
  rescue UserQuit
    show_score
  end

  def game_over
    puts "No valid moves... game over!\07"
    sleep 0.5
    show_score
  end

  def handle_input(slider)
    command = Input.next
    fail UserQuit if command == :quit
    slider.slide!(command)
  end

  def show_score
    score = Score.new(board)
    puts "You scored #{score} points."
  end
end
