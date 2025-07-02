
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
green: .word 0x0066CC00
orange: .word 0x00FFA500
red: .word 0x00e06666
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
collisionLocation: .word 0        # Corresponds to the exact coordinates where an enemy ship was hit
explosionCleanup: .word 0         # When an enemy explodes it makes an explosion effect, this is to indicate it needs to get cleaned up next game loop
enemyPosition: .word 640          # Starting location for the enemies to be drawn
skipUpdate: .word 0
aliveEnemies: .word 5             # Stores total enemies, used to easily check if you've won
enemyOneStatus: .word 1           # Status for enemies, 0: Dead 1: Alive 
enemyTwoStatus: .word 1
enemyThreeStatus: .word 1
enemyFourStatus: .word 1
enemyFiveStatus: .word 1
enemyProjectileCooldown: .word 0       # Initially zero so that the enemies fire at you at the beginning of the game, every 5 game loops a random enemy will shoot
enemyOneProjectilePosition: .word 0    # Stores position for each of the enemy's projectiles, also acts as a way of telling if they are active or not based on value
enemyTwoProjectilePosition: .word 0
enemyThreeProjectilePosition: .word 0
enemyFourProjectilePosition: .word 0
enemyFiveProjectilePosition: .word 0


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
    addi $a0, $zero, 50 # sleep time in ms
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
    jal updateEnemy
    j gameLoop

down:
    move $t3, $zero
    addi $t3, $t3, 128
    sw $t3, playerVelocity
    jal movePlr
    jal updatePlr
    jal updateEnemy
    j gameLoop

left:
    move $t3, $zero
    addi $t3, $t3, -4
    sw $t3, playerVelocity
    jal movePlr
    jal updatePlr
    jal updateEnemy
    j gameLoop

right:
    move $t3, $zero
    addi $t3, $t3, 4
    sw $t3, playerVelocity
    jal movePlr
    jal updatePlr
    jal updateEnemy
    j gameLoop

idle:
    move $t3, $zero
    sw $t3, playerVelocity
    jal updatePlr
    jal updateEnemy
    j gameLoop
    
shoot:
    move $t0, $zero
    addi $t0, $t0, 1
    sw $t0, playerProjectileState
    jal movePlr
    jal updatePlr
    jal updateEnemy
    j gameLoop
    
# Updates the player sprite, calls other funcitons to draw the ship and checks if the player has lost

updatePlr:
    addi $sp, $sp, -4             # Store $ra
    sw $ra, 0($sp)
  
    lw $t5, black                 # Load black color of the background
    lw $t6, white                 # Load white dot for the ship color
    jal drawShip                
    beq $t7, $zero, checkWin      # Checks if player has lost 
    
    li $v0, 4            # If player has died then display lose message and terminate program
    la $a0, lose
    syscall
    
    li $v0, 10
    syscall
    
    checkWin:
    lw $t8, aliveEnemies
    bnez $t8, updateProjectile  # Check and see if the number of enemies alive is 0
    li $v0, 4                   # If player has killed all the enemies then display win message and terminate program
    la $a0, win
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
    addi $t1, $t1, -128
    lw $t2, 0($t1)                       # Get the value of the second part of the new position
    beq $t2, $t3, drawProjectile         # Check and see if the second part has collided with anything
    jal playerProjectileCollision
    j playerProjectileExit
    
    drawProjectile:
    lw $t2, white
    sw $t2, 0($t1)                       # Draw updated bullet position if all checks pass
    sw $t2, 128($t1)
    
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
    
    # If player hits an enemy, store the collision location so that the updateEnemy function can look for which ship got hit
    enemyCollision:
    lw $t0, green
    bne $t0, $t2, exitPlayerProjectileCollision   # Check to see if it hit an enemy, if not, then it either collided with another bullet or some other thing i didnt account for
    sw $t1, collisionLocation                     # Stores collision location
    lw $t2, orange                                # Get orange dot for mini explosion animation
    sw $t2, 0($t1)                                # Put it on the screen for the first frame of the explosion animation, and also to indicate where the hit is located
    
    exitPlayerProjectileCollision:
    jr $ra

# Handles the erasing and drawing of each enemy frame
# Checks enemy status to make sure not to draw already defeated enemies
# Also checks to see if they enemies have decided to shoot at the player, which will branch to the enemyProjectileHandler
# If the enemy is dead, its respective projectile will remain, but it won't be able to fire or be drawn again
updateEnemy:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    lw $t0, explosionCleanup
    beqz $t0, checkForEnemyCollisionsNow
    lw $t1, black 
    sw $t1, -132($t0)             # Clean up explosion effect
    sw $t1, -124($t0)
    sw $t1, 132($t0)
    sw $t1, 124($t0)
    sw $zero, explosionCleanup 
   
    checkForEnemyCollisionsNow:   
    lw $t0, collisionLocation
    beqz $t0, noCollisionsRightNow    # If the enemy has been hit by a bullet, the location would have been stored, so check for that before changing anything to enemy position
    jal enemyCollisionHandler
    
    noCollisionsRightNow:
    lw $t0, skipUpdate
    bnez $t0, skipUpdatingEnemy
    move $t0, $zero
    addi $t0, $t0, 1
    sw $t0, skipUpdate

    lw $t0, black                         # Load color of the background
    la $t1, displaySpace                  # Get the display address
    lw $t2, enemyPosition                 # Get enemy position root position to be drawn from
    add $t1, $t1, $t2                     # Get the actual position
    
    jal drawEnemy
    
    lw $t0, green                         # Load green color of the alien ships
    la $t1, displaySpace                  # Get the display address again
    addi $t2, $t2, 4                      # Offset the position to move them for the next frame
    sw $t2, enemyPosition                 # Store new offset, that is one pixel to the right
    add $t1, $t1, $t2                     # Calculate actual position using new offset
    
    jal drawEnemy
    
    j updateEnemyAfter
    
    skipUpdatingEnemy:
    move $t0, $zero
    sw $t0, skipUpdate
    
    updateEnemyAfter:
    jal enemyProjectileHandler
    
    exitUpdateEnemy:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra
    
drawEnemy:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
 
    lw $t3, enemyOneStatus                # Get the first enemy's state
    beq $t3, $zero, enemy2draw            # If it is dead, skip over drawing it             
    jal drawEnemyFunction
    
    enemy2draw:
    addi $t1, $t1, 24                     # Jump 6 spaces over to draw the next enemy
    lw $t3, enemyTwoStatus
    beq $t3, $zero, enemy3draw       
    jal drawEnemyFunction
    
    enemy3draw:
    addi $t1, $t1, 24
    lw $t3, enemyThreeStatus
    beq $t3, $zero, enemy4draw       
    jal drawEnemyFunction
    
    enemy4draw:
    addi $t1, $t1, 24
    lw $t3, enemyFourStatus
    beq $t3, $zero, enemy5draw       
    jal drawEnemyFunction
    
    enemy5draw:
    addi $t1, $t1, 24
    lw $t3, enemyFiveStatus
    beq $t3, $zero, exitDrawEnemy    
    jal drawEnemyFunction
    
    exitDrawEnemy:
    
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra
    
# Draws the enemy by using the base position provided in $t1, and shifting around before returning back to the same spot 
# Returns to the original position to conserve the correct offset even if the ship is skipped, which would mess up the formula
drawEnemyFunction:
    sw $t0, 0($t1)
    
    addi $t1, $t1, -124     
    sw $t0, 0($t1)
    
    addi $t1, $t1, -128
    sw $t0, 0($t1)
    
    addi $t1, $t1, 132
    sw $t0, 0($t1)
    
    addi $t1, $t1, 128
    sw $t0, 0($t1)
    
    addi $t1, $t1, -124
    sw $t0, 0($t1)
    
    addi $t1, $t1, -128
    sw $t0, 0($t1)
    
    addi $t1, $t1 260
    sw $t0, 0($t1)
    
    addi $t1, $t1 -16  # Return to base position before exiting function
    
    jr $ra

enemyCollisionHandler:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    lw $t0, orange
    lw $t1, enemyPosition
    la $t2, displaySpace
    add $t1, $t1, $t2    # Get exact position where the enemies are being drawn from
    lw $t3, collisionLocation
    move $t4, $zero         # This increments each time an enemy is searched, used to determine which one got hit
    move $t5, $zero         # This is to indicate when the red dot has been found, so that the search can end
    jal collisionSearch
    
    sw $zero, collisionLocation
    lw $t0, black
    sw $t0, 0($t3)
    sw $t3, explosionCleanup      # Store the location of the collision to be cleaned up next time the enemy is updated
    lw $t0, red 
    sw $t0, -132($t3)             # Draw the explosion effect that will be cleaned up later
    sw $t0, -124($t3)
    sw $t0, 132($t3)
    sw $t0, 124($t3)
    
    
    exitEnemyCollisionHandler:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

collisionSearch:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    addi $t4, $t4, 1               # Keeps track of which enemy is being currently searched
    lw $t6, enemyOneStatus
    beqz $t6, searchTwo            # Don't need to search dead enemies
    jal collisionSearchFunction
    bnez $t5, bulletLocationFound  # If it has been found in this search, no need to search any other ships
    
    searchTwo:
    addi $t1, $t1, 24              # Offset to get to the next ship location
    addi $t4, $t4, 1              
    lw $t6, enemyTwoStatus
    beqz $t6, searchThree            
    jal collisionSearchFunction
    bnez $t5, bulletLocationFound  
    
    searchThree:
    addi $t1, $t1, 24 
    addi $t4, $t4, 1              
    lw $t6, enemyThreeStatus
    beqz $t6, searchFour           
    jal collisionSearchFunction
    bnez $t5, bulletLocationFound  
    
    searchFour:
    addi $t1, $t1, 24 
    addi $t4, $t4, 1              
    lw $t6, enemyFourStatus
    beqz $t6, searchFive          
    jal collisionSearchFunction
    bnez $t5, bulletLocationFound  
    
    searchFive:
    addi $t1, $t1, 24 
    addi $t4, $t4, 1                      
    jal collisionSearchFunction
    bnez $t5, bulletLocationFound 
    j exitCollisionSearch         # If for some reason there was a false flag, just exit the search
    
    bulletLocationFound:
    bne $t4, 1, shipTwoHitCheck
    sw $zero, enemyOneStatus
    lw $t0, aliveEnemies
    addi $t0, $t0, -1            # Reduce the amount of enemies alive by 1
    sw $t0, aliveEnemies
    j exitCollisionSearch
    
    shipTwoHitCheck:
    bne $t4, 2, shipThreeHitCheck
    sw $zero, enemyTwoStatus
    lw $t0, aliveEnemies
    addi $t0, $t0, -1
    sw $t0, aliveEnemies
    j exitCollisionSearch
    
    shipThreeHitCheck:
    bne $t4, 3, shipFourHitCheck
    sw $zero, enemyThreeStatus
    lw $t0, aliveEnemies
    addi $t0, $t0, -1
    sw $t0, aliveEnemies
    j exitCollisionSearch  
    
    shipFourHitCheck:
    bne $t4, 4, shipFiveHitCheck
    sw $zero, enemyFourStatus
    lw $t0, aliveEnemies
    addi $t0, $t0, -1
    sw $t0, aliveEnemies
    j exitCollisionSearch  
    
    shipFiveHitCheck:
    bne $t4, 5, shipFiveHitCheck
    sw $zero, enemyFiveStatus 
    lw $t0, aliveEnemies
    addi $t0, $t0, -1
    sw $t0, aliveEnemies
    
    exitCollisionSearch:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra
    
collisionSearchFunction:
    lw $t2, 0($t1)
    lw $t7, black
    sw $t7, 0($t1)                # Erase while searching since they're gonna get redrawn next update anyways, otherwise some bits of the ship can linger which is bad
    bne $t2, $t0, colSearchFind2  # See if this is the location marked with orange
    addi $t5, $t5, 1
    
    colSearchFind2:
    addi $t1, $t1, -124     
    lw $t2, 0($t1)
    sw $t7, 0($t1)               
    bne $t2, $t0, colSearchFind3
    addi $t5, $t5, 1
    
    colSearchFind3:
    addi $t1, $t1, -128
    lw $t2, 0($t1)
    sw $t7, 0($t1)
    bne $t2, $t0, colSearchFind4
    addi $t5, $t5, 1
    
    colSearchFind4:
    addi $t1, $t1, 132
    lw $t2, 0($t1)
    sw $t7, 0($t1)
    bne $t2, $t0, colSearchFind5
    addi $t5, $t5, 1
    
    colSearchFind5:
    addi $t1, $t1, 128
    lw $t2, 0($t1)
    sw $t7, 0($t1)
    bne $t2, $t0, colSearchFind6
    addi $t5, $t5, 1
    
    colSearchFind6:
    addi $t1, $t1, -124
    lw $t2, 0($t1)
    sw $t7, 0($t1)
    bne $t2, $t0, colSearchFind7
    addi $t5, $t5, 1
    
    colSearchFind7:
    addi $t1, $t1, -128
    lw $t2, 0($t1)
    sw $t7, 0($t1)
    bne $t2, $t0, colSearchFind8
    addi $t5, $t5, 1
    
    colSearchFind8:
    addi $t1, $t1 260
    lw $t2, 0($t1)
    sw $t7, 0($t1)
    bne $t2, $t0, noFind
    addi $t5, $t5, 1
    
    noFind:
    addi $t1, $t1 -16  # Return to base position before exiting function
       
    jr $ra

# First, this function generates a random number to get a random enemy to have shoot at the player, then it will use this random number to spawn it in front of the respective enemy
# This function only spawns a new bullet every 10 game cycles
enemyProjectileHandler:
    addi $sp, $sp, -4
    sw $ra 0($sp)
    
    lw $t0, enemyProjectileCooldown         # Get current cooldown for shooting
    bnez $t0, updateEnemyProjectiles        # If the cooldown has decremented to 0, try and spawn a projectile randomly
    li $s0, 10                              # Each time a number is generated, decrements this value. If it reaches 0, skips over spawning entirely to prevent infinite loops.
    li $t0, 8                               # Reset the cooldown for shooting
    sw $t0, enemyProjectileCooldown        
    lw $t1, enemyPosition                  # Get enemy position 
    la $t2, displaySpace 
    add $t1, $t1, $t2                      # Get real position on the display 
    redoRandom:
    addi $a1, $zero, 5                     # Syscall function for generating a random number, generates a random number from 0-4 for all the enemy ships
    addi $v0, $zero, 42   
    syscall
    beqz $s0, updateEnemyProjectiles       # If the threshold is reached (10 tries), then skip over generating entirely, likely it is the last few enemies alive and they're shooting
    
    enemyProjectileHandler1: 
    move $t2, $zero                        # 0 = 1st enemy
    bne $a0, $t2, enemyProjectileHandler2  # Skip over if the number doesn't correspond to this enemy
    addi $s0, $s0, -1                      # Decrement number generation count
    lw $t2, enemyOneStatus                 # Get the alive or dead status of enemy
    beqz $t2, redoRandom                   # Redo the random call if the enemy is dead
    lw $t2, enemyOneProjectilePosition     # Get the projectile position for this enemy from memory
    bnez $t2, redoRandom                   # Redo the random call if the first enemy already has a projectile out
    jal enemyProjectileSpawn
    sw $t1, enemyOneProjectilePosition     # If it is drawn, skip to update any other spawned projectiles
    j updateEnemyProjectiles
    
    enemyProjectileHandler2:
    addi $t2, $t2, 1                       # 1 = 2nd enemy
    bne $a0, $t2, enemyProjectileHandler3  
    addi $s0, $s0, -1                      
    lw $t2, enemyTwoStatus                 
    beqz $t2, redoRandom                   
    lw $t2, enemyTwoProjectilePosition     
    bnez $t2, redoRandom                   
    addi $t1, $t1, 24                     # If it passes all checks and is ready for spawning, then offset based on enemy number
    jal enemyProjectileSpawn
    sw $t1, enemyTwoProjectilePosition
    j updateEnemyProjectiles
    
    enemyProjectileHandler3:
    addi $t2, $t2, 2                       # 2 = 3rd enemy
    bne $a0, $t2, enemyProjectileHandler4  
    addi $s0, $s0, -1                      
    lw $t2, enemyThreeStatus                 
    beqz $t2, redoRandom                   
    lw $t2, enemyThreeProjectilePosition     
    bnez $t2, redoRandom                   
    addi $t1, $t1, 48                     
    jal enemyProjectileSpawn
    sw $t1, enemyThreeProjectilePosition
    j updateEnemyProjectiles
    
    enemyProjectileHandler4:
    addi $t2, $t2, 3                       # 3 = 4th enemy
    bne $a0, $t2, enemyProjectileHandler5  
    addi $s0, $s0, -1                      
    lw $t2, enemyFourStatus                 
    beqz $t2, redoRandom                   
    lw $t2, enemyFourProjectilePosition     
    bnez $t2, redoRandom                   
    addi $t1, $t1, 72                     
    jal enemyProjectileSpawn
    sw $t1, enemyFourProjectilePosition
    j updateEnemyProjectiles
    
    enemyProjectileHandler5:
    addi $t2, $t2, 4                       # 4 = 5th enemy  
    addi $s0, $s0, -1                      # bne ommited because it would be outside the random number generation range (impossible)
    lw $t2, enemyFiveStatus                 
    beqz $t2, redoRandom                   
    lw $t2, enemyFiveProjectilePosition     
    bnez $t2, redoRandom                   
    addi $t1, $t1, 96                     
    jal enemyProjectileSpawn
    sw $t1, enemyFiveProjectilePosition   
       
    
    updateEnemyProjectiles:
    lw $t0, enemyOneProjectilePosition
    beqz $t0, updateEnemyProj2           # If it hasn't been spawned yet, no need to update
    jal updateEnemyProjectile
    bnez $t3, enemyProj1Good
    sw $zero, enemyOneProjectilePosition # If the bullet collided with the border, reset its position so it is effectively despawned
    j updateEnemyProj2
    
    enemyProj1Good:
    sw $t0, enemyOneProjectilePosition   # If the bullet did not collide with the border, store the new updated position
    
    updateEnemyProj2:
    lw $t0, enemyTwoProjectilePosition
    beqz $t0, updateEnemyProj3           # If it hasn't been spawned yet, no need to update
    jal updateEnemyProjectile
    bnez $t3, enemyProj2Good
    sw $zero, enemyTwoProjectilePosition # If the bullet collided with the border, reset its position so it is effectively despawned
    j updateEnemyProj3
    
    enemyProj2Good:
    sw $t0, enemyTwoProjectilePosition   # If the bullet did not collide with the border, store the new updated position
    
    updateEnemyProj3:
    lw $t0, enemyThreeProjectilePosition
    beqz $t0, updateEnemyProj4           # If it hasn't been spawned yet, no need to update
    jal updateEnemyProjectile
    bnez $t3, enemyProj3Good
    sw $zero, enemyThreeProjectilePosition # If the bullet collided with the border, reset its position so it is effectively despawned
    j updateEnemyProj4
    
    enemyProj3Good:
    sw $t0, enemyThreeProjectilePosition   # If the bullet did not collide with the border, store the new updated position
    
    updateEnemyProj4:
    lw $t0, enemyFourProjectilePosition
    beqz $t0, updateEnemyProj5           # If it hasn't been spawned yet, no need to update
    jal updateEnemyProjectile
    bnez $t3, enemyProj4Good
    sw $zero, enemyFourProjectilePosition # If the bullet collided with the border, reset its position so it is effectively despawned
    j updateEnemyProj5
    
    enemyProj4Good:
    sw $t0, enemyFourProjectilePosition   # If the bullet did not collide with the border, store the new updated position
    
    updateEnemyProj5:
    lw $t0, enemyFiveProjectilePosition
    beqz $t0, exitEnemyProjectileHandler # If it hasn't been spawned yet, no need to update
    jal updateEnemyProjectile
    bnez $t3, enemyProj5Good
    sw $zero, enemyFiveProjectilePosition # If the bullet collided with the border, reset its position so it is effectively despawned
    j exitEnemyProjectileHandler
    
    enemyProj5Good:
    sw $t0, enemyFiveProjectilePosition   # If the bullet did not collide with the border, store the new updated position
    
    exitEnemyProjectileHandler:
    lw $t0, enemyProjectileCooldown       # Reduce cooldown every time the enemy is updated
    addi $t0, $t0, -1
    sw $t0, enemyProjectileCooldown    
    
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

enemyProjectileSpawn:
    addi $t1, $t1, 264                # offset to be just below the respective spaceship
    lw $t2, red                       # get red for enemy bullets (they are red)
    sw $t2, 0($t1)
    sw $t2, 128($t1)
    jr $ra
    
updateEnemyProjectile:
    lw $t2, black                            # Erase previous frame of the enemy bullet
    sw $t2, 0($t0)
    sw $t2, 128($t0)
    addi $t0, $t0, 256                       # Offset to be the next space before updating
    lw $t1, 0($t0)                           # get the value at the next space
    lw $t2, gray                             # Get gray color of border    
    bne $t2, $t1, firstEnemyProjValid        # If it is not gray, skip over, no need to consider player since they will lose when looping back to playerUpdate, and projectiles dont matter
    move $t3, $zero                          # $t3 is used to indicate if there needs to be a despawn of the projectile, or if its okay to keep updating it
    j exitUpdateEnemyProjectile              # Skip to the end if there is a collision, no need to update
    
    firstEnemyProjValid:
    addi $t0, $t0, 128                       # Do the same as before, but just offset a space downwards to check the next spot for the projectile
    lw $t1, 0($t0)
    bne $t2, $t1, updateEnemyProjectileDraw
    move $t3, $zero
    j exitUpdateEnemyProjectile
    
    updateEnemyProjectileDraw:
    lw $t2, red                             # Get red color for enemy bullet
    sw $t2, 0($t0)                          # Draw the bullet
    addi $t0, $t0, -128                     # Offset back to get to the original position (so that the math doesn't get messed up at beginning of this function)
    sw $t2, 0($t0)                          # Draw the bullet
    move $t3, $zero                         # reset just incase successive successful projectile calls messes things up, i doubt it though
    addi $t3, $t3, 1                        # 1 indicates everything is okay
    
    exitUpdateEnemyProjectile:
    jr $ra
    
    
