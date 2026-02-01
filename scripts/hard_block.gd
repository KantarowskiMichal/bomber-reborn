extends StaticBody2D
class_name HardBlock
## Indestructible wall block that cannot be destroyed by explosions.
##
## Hard blocks form the arena structure:
## - Border around the edge of the arena
## - Pillars at every even (x, y) coordinate inside the arena
##
## Hard blocks stop explosions from spreading through them.
## They use a darker color to distinguish from soft blocks.
##
## This class has no logic - it exists purely as a collision body
## and for type identification by the explosion system.
