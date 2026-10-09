enum SampleSpec {
    static let yaml = #"""
openapi: 3.1.0
info:
  title: JSONPlaceholder
  version: "1.0"
  description: |
    A free fake REST API for testing and prototyping, described as OpenAPI so you can explore Specline.

    Every request here goes to the live service at jsonplaceholder.typicode.com. Writes are accepted and echoed back, but nothing is stored.
servers:
  - url: https://jsonplaceholder.typicode.com
    description: Production
tags:
  - name: Posts
    description: Blog posts written by users.
  - name: Comments
    description: Comments left on posts.
  - name: Users
    description: People who write posts and own todos.
  - name: Todos
    description: Task lists for each user.
paths:
  /posts:
    get:
      tags: [Posts]
      operationId: listPosts
      summary: List posts
      description: Returns every post. Filter by author with the userId query parameter.
      parameters:
        - name: userId
          in: query
          description: Only return posts written by this user.
          schema:
            type: integer
            example: 1
        - name: _limit
          in: query
          description: Limit the number of results.
          schema:
            type: integer
            example: 5
      responses:
        "200":
          description: A list of posts.
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: "#/components/schemas/Post"
    post:
      tags: [Posts]
      operationId: createPost
      summary: Create a post
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/NewPost"
      responses:
        "201":
          description: The created post, with its new id.
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Post"
  /posts/{id}:
    parameters:
      - name: id
        in: path
        required: true
        description: The post id, from 1 to 100.
        schema:
          type: integer
          example: 1
    get:
      tags: [Posts]
      operationId: getPost
      summary: Get a post
      responses:
        "200":
          description: The post.
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Post"
        "404":
          description: No post has this id.
    put:
      tags: [Posts]
      operationId: replacePost
      summary: Replace a post
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/Post"
      responses:
        "200":
          description: The replaced post.
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Post"
    patch:
      tags: [Posts]
      operationId: updatePost
      summary: Update part of a post
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                title:
                  type: string
                  example: A better title
      responses:
        "200":
          description: The updated post.
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Post"
    delete:
      tags: [Posts]
      operationId: deletePost
      summary: Delete a post
      responses:
        "200":
          description: The post was deleted.
  /posts/{id}/comments:
    get:
      tags: [Comments]
      operationId: listPostComments
      summary: List comments on a post
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: integer
            example: 1
      responses:
        "200":
          description: Comments on the post.
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: "#/components/schemas/Comment"
  /users:
    get:
      tags: [Users]
      operationId: listUsers
      summary: List users
      responses:
        "200":
          description: Every user.
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: "#/components/schemas/User"
  /users/{id}:
    get:
      tags: [Users]
      operationId: getUser
      summary: Get a user
      parameters:
        - name: id
          in: path
          required: true
          description: The user id, from 1 to 10.
          schema:
            type: integer
            example: 1
      responses:
        "200":
          description: The user.
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/User"
  /todos:
    get:
      tags: [Todos]
      operationId: listTodos
      summary: List todos
      parameters:
        - name: completed
          in: query
          schema:
            type: boolean
        - name: userId
          in: query
          schema:
            type: integer
            example: 1
      responses:
        "200":
          description: Matching todos.
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: "#/components/schemas/Todo"
components:
  schemas:
    NewPost:
      type: object
      required: [title, body, userId]
      properties:
        title:
          type: string
          description: The headline of the post.
          example: Hello from Specline
        body:
          type: string
          description: The full text of the post.
          example: Spec first API testing, on the Mac.
        userId:
          type: integer
          description: The author.
          example: 1
    Post:
      allOf:
        - $ref: "#/components/schemas/NewPost"
        - type: object
          required: [id]
          properties:
            id:
              type: integer
              readOnly: true
              example: 1
    Comment:
      type: object
      required: [id, postId, name, email, body]
      properties:
        id:
          type: integer
        postId:
          type: integer
        name:
          type: string
        email:
          type: string
          format: email
        body:
          type: string
    User:
      type: object
      required: [id, name, username, email]
      properties:
        id:
          type: integer
        name:
          type: string
          example: Leanne Graham
        username:
          type: string
          example: Bret
        email:
          type: string
          format: email
        phone:
          type: string
        website:
          type: string
        address:
          $ref: "#/components/schemas/Address"
        company:
          type: object
          properties:
            name:
              type: string
            catchPhrase:
              type: string
            bs:
              type: string
    Address:
      type: object
      properties:
        street:
          type: string
        suite:
          type: string
        city:
          type: string
        zipcode:
          type: string
        geo:
          type: object
          properties:
            lat:
              type: string
            lng:
              type: string
    Todo:
      type: object
      required: [id, userId, title, completed]
      properties:
        id:
          type: integer
        userId:
          type: integer
        title:
          type: string
        completed:
          type: boolean
"""#
}
