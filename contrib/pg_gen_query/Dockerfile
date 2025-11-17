FROM postgres:14

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential cmake pkg-config git ca-certificates wget \
    libssl-dev zlib1g-dev libbrotli-dev postgresql-server-dev-14 \
    nlohmann-json3-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Copy the whole repository into the image so CMake can locate ai-sdk-cpp
COPY . /workspace

WORKDIR /workspace/contrib/pg_gen_query

# Build the pg_gen_query extension directly from the contrib folder.
# Provide an empty AI_SDK_TARGET so the contrib CMakeLists doesn't require
# an installed `ai::` target inside the image.
# Copy the built extension into Postgres lib dir (built in /workspace/build)
RUN ls -la /workspace \
  && rm -rf /workspace/build \
    && cmake -S /workspace -B /workspace/build -DBUILD_EXAMPLES=OFF -DBUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CXX_STANDARD=20 -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=ON \
    && cmake --build /workspace/build -- -j1 \
    && cmake --install /workspace/build --prefix /usr/local

# Now build the contrib extension against the installed SDK
RUN rm -rf /workspace/contrib/pg_gen_query/build \
    && cmake -S /workspace/contrib/pg_gen_query -B /workspace/contrib/pg_gen_query/build \
      -DCMAKE_CXX_STANDARD=20 -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    && cmake --build /workspace/contrib/pg_gen_query/build -- -j1

# Copy the built extension into Postgres lib dir
RUN cp /workspace/contrib/pg_gen_query/build/pg_gen_query.so $(pg_config --pkglibdir)

# Install extension metadata so CREATE EXTENSION can find it
RUN mkdir -p $(pg_config --sharedir)/extension \
  && cp /workspace/contrib/pg_gen_query/pg_gen_query.control $(pg_config --sharedir)/extension/ \
  && cp /workspace/contrib/pg_gen_query/pg_gen_query--1.0.sql $(pg_config --sharedir)/extension/ \
  && cp /workspace/contrib/pg_gen_query/register_function.sql $(pg_config --sharedir)/extension/

# Add the startup helper that starts postgres, runs setup, then drops to a shell
COPY contrib/pg_gen_query/start-and-shell.sh /usr/local/bin/start-and-shell.sh
RUN chmod +x /usr/local/bin/start-and-shell.sh

EXPOSE 5432

# Ensure default Postgres data directory environment and run as postgres user
ENV PGDATA=/var/lib/postgresql/data
USER postgres
CMD ["/usr/local/bin/start-and-shell.sh"]
