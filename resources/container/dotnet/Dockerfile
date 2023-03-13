FROM mcr.microsoft.com/dotnet/sdk:7.0 AS build

WORKDIR /source
COPY . ./

# Build and publish a release
RUN dotnet publish -c Release -o /out

# Build runtime image
FROM mcr.microsoft.com/dotnet/runtime:7.0
WORKDIR /App
COPY --from=build /out .
ENTRYPOINT ["dotnet", "app.dll"]
