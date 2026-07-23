FROM maven:3.8.6-openjdk-8 AS build

WORKDIR /app
COPY pom.xml .
COPY src ./src

RUN mvn clean package -DskipTests

FROM eclipse-temurin:8-jre-alpine

WORKDIR /app
COPY --from=build /app/target/java8-gateway-1.0.0.jar app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-Duser.timezone=America/Mexico_City", "-jar", "app.jar"]

