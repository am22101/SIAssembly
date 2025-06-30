
# Author: Aidan McSweeney                           
# Description: A game similar to the classic space invaders made for MARS 4.5                                                                               

# Bitmap Display Settings
# 
# Unit Width in pixels: 8
# Unit Height in pixels: 8
# Display Width in Pixels: 256
# Display Height in Pixels: 512
# Base address for display: 0x10010000 (static data)

.data
displaySpace: .space 0x80000       # 256 x 512 x 4
lose: .asciiz "YOU LOSE"
win:  .asciiz "YOU WIN"
black: .word  0x00000000
white: .word  0x00FFFFFF
gray: .word 0x00999999
plrIdle: .word 0                   # Placeholder values to store and compare movement state
plrUp: .word 1
plrDown: .word 2
plrLeft: .word 3
plrRight: .word 4
playerPosition: .word 6464        # Using conversion equation: address = BASE_ADDR + (y * 32) + (x * 4), with the starting position at x:16 y:50, bottom middle
                                  # Move up: subtract 128
                                  # Move down: add 128
                                  # Move right: add 4
                                  # Move left: subtract 4
playerVelocity: .word 0           # Mostly used to prevent issues when shooting projectiles while moving
playerProjectilePosition: .word 0 # Stores the exact positon of the projectile that the player has fired
playerProjectileState: .word 0    # 0 = no projectile, 1 = projectile has been fired


.text

### Draws a gray border around the top and bottom of the screen to prevent out of bounds index errors

drawBorder:
    la $t0, displaySpace   # Loads $t0 with the first pixel in the display address
    li $t1, 32             # 256 / 8 = 32 units across the top
    lw $t2, gray           # Loads the gray color which will remain unchanged
    
    drawTop:
        sw $t2, 0($t0)
        addi $t0, $t0, 4
        addi $t1, $t1, -1
        bnez $t1, drawTop  # Once 32 units have been drawn, end loop
        
    la $t0, displaySpace  # Reload display space
    li $t1, 32
    addi $t0, $t0, 8064
    
    drawBottom:
        sw $t2, 0($t0)
        addi $t0, $t0, 4
        addi $t1, $t1, -1
        bnez $t1, drawBottom
        
# Loops infinitely until player loses
# Sleeps and then gets player input, of which the acceptable values are:
# W - Move up
# A - Move left
# S - Move down
# D - Move Right
# Spacebar - Stop moving (idle)
# F - Shoot projectile

gameLoop:
    
    addi $v0, $zero, 32  # Syscall for sleep
    addi $a0, $zero, 150 # sleep time in ms
    syscall   
    
    lw	$t4, 0xffff0004	# Address for keyboard input using Keyboard and Display MMIO
    
    beq	$t4, 119, up     # ASCII 'w'
    beq $t4, 115, down   # ASCII 's'
    beq $t4, 97, left    # ASCII 'a'
    beq $t4, 100, right  # ASCII 'd'
    beq $t4, 32, idle    # ASCII 'SPACE'
    beq $t4, 102, shoot    # ASCII 'f'
    beq $t4, 0, idle     # base case is not moving 

up:
    move $t3, $zero      # Reset velocity
    addi $t3, $t3, -128
    sw $t3, playerVelocity
    jal movePlr
    jal updatePlr
    j gameLoop

down:
    move $t3, $zero
    addi $t3, $t3, 128
    sw $t3, playerVelocity
    jal movePlr
    jal updatePlr  
    j gameLoop

left:
    move $t3, $zero
    addi $t3, $t3, -4
    sw $t3, playerVelocity
    jal movePlr
    jal updatePlr 
    j gameLoop

right:
    move $t3, $zero
    addi $t3, $t3, 4
    sw $t3, playerVelocity
    jal movePlr
    jal updatePlr
    j gameLoop

idle:
    move $t3, $zero
    sw $t3, playerVelocity
    jal updatePlr
    j gameLoop
    
shoot:
    move $t0, $zero
    addi $t0, $t0, 1
    sw $t0, playerProjectileState
    jal movePlr
    jal updatePlr
    j gameLoop
    
# Updates the player sprite, calls other funcitons to draw the ship and checks if the player has lost

updatePlr:
    addi $sp, $sp, -4             # Store $ra
    sw $ra, 0($sp)
  
    lw $t5, black                 # Load black color of the background
    lw $t6, white                 # Load white dot for the ship color
    jal drawShip                
    beq $t7, $zero, updateProjectile # Checks if player has lost 
    
    li $v0, 4            # If player has died then display lose message and terminate program
    la $a0, lose
    syscall
    
    li $v0, 10
    syscall
    
    updateProjectile:
    lw $t0, playerProjectileState    # Get player projectile state from memory
    beqz $t0, noProjectile           # Check if there is a projectile out, if not, finish updating player state
    jal playerProjectileHandler
    
    noProjectile:
    lw $ra, 0($sp)
    addi $sp, $sp, 4             # Restore the stack
    jr $ra
    
# Function draws the entire ship and also checks if the player has lost
# Achieves this function by taking the root position in $t0 and modifying it to draw the ship by some numerical shifts
# Draws the entire ship regardless of whether the player has lost or not, to prevent the sprite looking weird if loss condition is found while drawing
# Stores the "loss value" in $t6, if at any time while drawing it notices a projectile or wall has collided with the player, it will increment it
# Once returning to the caller, it will check whether $t6 is greater than 0, if it is, it will terminate the program.

drawShip:
     addi $sp, $sp, -4
     sw $ra, 0($sp)
     
     lw $t0, playerPosition        # Get players current position
     la $t1, displaySpace          # Load the display address
     add $t0, $t0, $t1             # Add the position of the player to the base address
     
     jal drawFunction
     
     addi $t0, $t0, -8         # Calculate next space for drawing the spaceship sprite
     jal drawFunction        
     
     addi $t0, $t0, 16   
     jal drawFunction
     
     addi $t0, $t0, -132   
     jal drawFunction
     
     addi $t0, $t0, -8   
     jal drawFunction
     
     addi $t0, $t0, -124  
     jal drawFunction
     
     addi $t0, $t0, -128   
     jal drawFunction
     
     lw $ra, 0($sp)           
     addi $sp, $sp 4          # Restore the stack
     jr $ra

# Main drawing function for drawShip 
drawFunction:
     lw $t2, 0($t0)         # Get the color of the current position on the ship              
     sw $t6, 0($t0)         # Draw white dot on the display  
     beq $t2, $t5, noLoss   # Compare to see if anything has collided with ship
     beq $t2, $t6, noLoss   # Compare to see if the ship is idling
     addi $t7, $t7, 1       # $t7 increments "loss value"
     noLoss:
     jr $ra           
     
# Cleans up the previous "frame" by erasing the ship based on the current players root position
movePlr:    
    lw $t0, playerPosition   # Get player position and display address
    la $t1, displaySpace     
    add $t1, $t0, $t1        # Calculate old player position on displayMap
    lw $t2, black            # Load black color for "erasing"
    sw $t2, 0($t1)           # Display the black color on the root player position
    
    addi $t1, $t1, -8        # Draw black over the rest of the ship
    sw $t2, 0($t1)
    
    addi $t1, $t1, 16 
    sw $t2, 0($t1)
    
    addi $t1, $t1, -132 
    sw $t2, 0($t1)
    
    addi $t1, $t1, -8 
    sw $t2, 0($t1)
    
    addi $t1, $t1, -124 
    sw $t2, 0($t1)
    
    addi $t1, $t1, -128
    sw $t2, 0($t1)
    
    lw $t3, playerVelocity
    add $t0, $t0, $t3        # Update and store new player position 
    sw $t0, playerPosition    

    jr $ra

# This function handles how the player's projectile is updated once it has been fired, moving it up across the screen
# It also checks whether or not the projectile has collided with anything by comparing the next space it would occupy with the color of the background
playerProjectileHandler:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
     
    lw $t1, playerProjectilePosition     # Get the projectile position from memory
    bnez $t1, playerProjectileMain       # Check if it is being spawned for the first time
    lw $t0, playerPosition               # Gets the players root position
    la $t2, displaySpace                 # Load the display address
    add $t0, $t0, $t2                    # Add the base address to the projectile
    addi $t0, $t0, -640                  # Sets position to be right in front of the ship, where the projectile should be initially spawned
    sw $t0, playerProjectilePosition     # Stores the position of the new projectile
    lw $t3, white                        # Get the color of the bullet
    sw $t3, 0($t0)                       # Draw Bullet
    sw $t3, -128($t0)
    j playerProjectileExit               # Exit after spawning projectile for the first time                        
    
    playerProjectileMain:
    lw $t0, black                        # Get black color of the background
    sw $t0, 0($t1)                       # "erase" the previous frame of the projectile
    sw $t0, -128($t1)
    addi $t1, $t1, -256                  # Update position of the projectile
    sw $t1, playerProjectilePosition     # Store new value of the projectile position
    lw $t2, 0($t1)                       # Get the value of the first part of the new position 
    lw $t3, black                        # Get the color of the background
    beq $t2, $t3, validPlayerProjectile1 # Check and see if the first part has collided with anything
    jal playerProjectileCollision
    j playerProjectileExit
    
    validPlayerProjectile1:
    lw $t2, -128($t1)                    # Get the value of the second part of the new position
    beq $t2, $t3, drawProjectile         # Check and see if the second part has collided with anything
    jal playerProjectileCollision
    j playerProjectileExit
    
    drawProjectile:
    lw $t2, white
    sw $t2, 0($t1)                       # Draw updated bullet position if all checks pass
    sw $t2, -128($t1)
    
    playerProjectileExit:
    lw $ra, 0($sp)           
    addi $sp, $sp 4
    jr $ra
    
playerProjectileCollision:
    lw $t0, gray                       # Get the color of the border
    bne $t0, $t2, enemyCollision       # Check and see if it has collided with the border or not
    sw $zero, playerProjectilePosition # If it collided with a wall, reset the projectile values to delete it
    sw $zero, playerProjectileState  
    
    jr $ra
    
    # Stub: Implement enemy collision handling
    enemyCollision:
    jr $ra
    

    


    
