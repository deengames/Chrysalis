require 'ostruct'
require_relative 'system/display_system'
require_relative 'system/input_system'
require_relative 'io/audio_manager'
require_relative 'io/keys'
require_relative 'utils/color'
require_relative 'model/entity'
require_relative 'component/input_component'
require_relative 'model/dungeon'
require 'json'

class Game

	attr_reader :current_map
	
	def initialize
		@display = DisplaySystem.new
		@input = InputSystem.new
	end
	
	def start
		begin
			### Make sure all requires are called before this or the executable will crash			
			exit if defined?(Ocra)			
			
			game_data = OpenStruct.new(JSON.parse(File.read('data/game.json')))
			if game_data.starting_map.nil?
				raise 'Game definition is missing a starting map ("starting_map" property); please tell it which map to start on.'
			end
			
			if (!File.exists?("data/maps/#{game_data.starting_map}"))
				raise "Starting map (data/maps/#{game_data.starting_map}) seems to be missing."
			end
			
			# Load entitiy/component definitions			
			@component_definitions = game_data.components
			
			# Load the starting map.
			@current_map = OpenStruct.new(JSON.parse(File.read("data/maps/#{game_data.starting_map}")))
			@current_map.floor = 0
			change_map(@current_map)
			@display.clear # change_map draws dots, but we can't init the display any later
			
			audio = AudioManager.new() # Convert to audio System; pass entities
			
			### Draw the titlescreen ###
			@display.draw_text(35, 10, game_data.name.upcase, Color.new(255, 0, 0))
			@display.draw_text(30, 12, 'Press any key to begin.', Color.new(255, 255, 255))
			@input.get_input
			
			### Draw the story ###
			if (!game_data.story.nil?) then
				@display.clear				
				@display.draw_text(0, 0, game_data.story, Color.new(192, 192, 192))
				@input.get_input
			end
			
			# Start drawing the main map
			@display.fill_screen('.', Color.new(128, 128, 128))
			@display.draw
			
			quit = false
			while (!quit) do
				@display.draw
				input = @input.get_and_process_input
				quit = (input == 'q' || input == 'escape')				
			end
			Logger.info('Normal termination')
		rescue StandardError => e
			Logger.info("Termination by error: #{e}")
			@display.destroy unless @display.nil?
			raise # Re-raise after cleaning up
		end
	end
	
	def create_entities_for(map)
		entities = []
		grey = Color.new(192, 192, 192)
		
		if map.respond_to?('perimeter') && map.perimeter == true
			(0 .. map.width).each do |x|
				# NOT classes. Wall is a bunch of components and data.
				# Components = DisplayComponent(x, y, char, color)
				# That's all data. There's no code here. Yet.
				# Old-style would be to have a MoveComponent instance in Player entity.
				# NewStyle is an empty "move" tag in the entity, and the MoveSystem operates on that.
				
				# TODO: we have some common entities (eg. walls) and components (eg. display), irrespective of game content
				# TODO: move this into a standard place for construction
				entities << Entity.new({ :x => x, :y => 0, :character => '#', :color => grey })
				entities << Entity.new({ :x => x, :y => map.height - 1, :character => '#', :color => grey })
			end
						
			(0 .. map.height).each do |y|
				entities << Entity.new({ :x => 0, :y => y, :character => '#', :color => grey })
				entities << Entity.new({ :x => map.width - 1, :y => y, :character => '#', :color => grey })
			end
		end
		
		if map.respond_to?('stairs') && !map.stairs.nil? then
			entities << Entity.new({
				:solid => false, :x => map.stairs['x'], :y => map.stairs['y'], :character => ">", :color => Color.new(255, 255, 255),
				:input => InputComponent.new(Proc.new { |input| change_map(Dungeon.new(@current_map.floor + 1)) if input == '>' })
			})			
		end
		
		if map.respond_to?('npcs') && !map.npcs.nil?
			(map.npcs).each do |npc|				
				entities << Entity.new({ :x => npc['x'], :y => npc['y'], :character => '@',
				:color => Color.new(npc['color']['r'], npc['color']['g'], npc['color']['b'])})
			end
		end
		
		if map.respond_to?('walls') && !map.walls.nil? then				
			white = Color.new(255, 255, 255)
			map.walls.each do |w|
				entities << Entity.new({ :x => w[0], :y => w[1], :character => "#", :color => white })
			end
		end
		
		player = Entity.new({
			# For identification
			:name => 'Player',
			# Display properties
			:x => map.start_x.to_i, :y => map.start_y.to_i, :character => "@", :color => Color.new(255, 192, 32)
		})		
		
		entities << player
		
		return entities
	end
	
	def change_map(new_map)
		@current_map = new_map
		
		@entities = create_entities_for(@current_map)			
		player = @entities.find { |e| e.has?(:name) && e.name == 'Player' }
		
		# Pass entities to our systems	
		@display.init(@entities) # replace map with entities
		@input.init(@entities, player)
		
		@display.fill_screen('.', Color.new(128, 128, 128))
	end
end
